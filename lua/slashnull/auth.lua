-- Signing in: approve this machine's key as a device, the way the mobile app
-- does. The app opens /mobile/authorize with a PKCE challenge, the user taps
-- Approve, and the app redeems the one-time code at /api/v1/devices. Here the
-- Approve is sent with the browser's session cookie, which is used for that
-- and never stored. The device then shows up in Settings > Devices on the web,
-- where it can be revoked.

local api = require("slashnull.api")
local config = require("slashnull.config")
local util = require("slashnull.util")

local M = {}

-- Written once the key is approved, so an abandoned login never polls.
M.approved_file = vim.fs.joinpath(config.data_dir, "approved")

function M.approved()
	return vim.uv.fs_stat(M.approved_file) ~= nil
end

function M.forget()
	os.remove(M.approved_file)
end

--- The device key, made on first use. It is only ever an approved device of
--- /dev/null, never a key on the GitHub account.
---@return string? fingerprint
local function ensure_key()
	if not vim.uv.fs_stat(api.key_file) then
		vim.fn.mkdir(config.data_dir, "p", "0700")
		local comment = "slashnull@" .. vim.uv.os_gethostname()
		local out = vim.system({ "ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", comment, "-f", api.key_file }, { text = true }):wait()
		if out.code ~= 0 then
			util.notify("could not make a key: " .. vim.trim(out.stderr), vim.log.levels.ERROR)
			return nil
		end
	end
	local out = vim.system({ "ssh-keygen", "-l", "-E", "sha256", "-f", api.key_file .. ".pub" }, { text = true }):wait()
	return out.stdout:match("SHA256:%S+")
end

--- A request to the web as the browser session in `cookie`.
---@return string body, string status, string inertia_version, string location
local function web(cookie, args)
	local cmd = {
		"curl",
		"--disable",
		"--silent",
		"--proto",
		"=https",
		"--max-time",
		"20",
		"--cookie",
		cookie,
		"--write-out",
		"\n%{http_code} %header{x-inertia-version} %header{location}",
	}
	vim.list_extend(cmd, args)
	local out = vim.system(cmd, { text = true }):wait()
	local body, status, version, location = (out.stdout or ""):match("^(.*)\n(%d+) (%S*) ?(%S*)$")
	return body or "", status or "000", version or "", location or ""
end

local function url_decode(s)
	return (s:gsub("%+", " "):gsub("%%(%x%x)", function(h)
		return string.char(tonumber(h, 16))
	end))
end

--- Approve the device key from the browser session in `cookie` and return the
--- one-time code, as tapping Approve on /mobile/authorize does.
---@return string? code, string? err
local function authorize(cookie, params)
	local query = {}
	for k, v in vim.spairs(params) do
		table.insert(query, ("%s=%s"):format(k, vim.uri_encode(v, "rfc3986")))
	end
	local page_url = config.url .. "/mobile/authorize?" .. table.concat(query, "&")

	-- The page as Inertia JSON, for the CSRF token and the signed-in user. The
	-- first answer is a 409 that tells the current asset version.
	local inertia = { "--header", "X-Inertia: true", "--header", "X-Requested-With: XMLHttpRequest" }
	local body, status, version = web(cookie, vim.list_extend(vim.list_extend({}, inertia), { page_url }))
	if status == "409" then
		body, status = web(cookie, vim.list_extend(vim.list_extend({ "--header", "X-Inertia-Version: " .. version }, inertia), { page_url }))
	end
	local ok, page = pcall(vim.json.decode, body)
	local props = ok and type(page) == "table" and page.props or {}
	local user = type(props.auth) == "table" and props.auth.user
	if status ~= "200" or type(user) ~= "table" then
		return nil, "the cookie is not signed in"
	end
	if props.error then
		return nil, props.error
	end

	local answer = vim.fn.confirm(("Approve Neovim on %s as a device of @%s?"):format(params.device_name, user.username), "&Yes\n&No", 2)
	if answer ~= 1 then
		return nil, nil
	end

	local form = { "--request", "POST", "--header", "Origin: " .. config.url, "--header", "Referer: " .. page_url }
	vim.list_extend(form, { "--data-urlencode", "_token=" .. props.csrfToken })
	for k, v in pairs(params) do
		vim.list_extend(form, { "--data-urlencode", ("%s=%s"):format(k, v) })
	end
	table.insert(form, config.url .. "/mobile/authorize")
	local _, post_status, _, location = web(cookie, form)
	local code = location:match("[?&]code=([^&]+)")
	local state = location:match("[?&]state=([^&]+)")
	if post_status ~= "303" or not code then
		return nil, "approval failed (HTTP " .. post_status .. ")"
	end
	if url_decode(state or "") ~= params.state then
		return nil, "approval came back for another request"
	end
	return url_decode(code)
end

--- Approve this machine as a device. Needs the browser's `Cookie` header for
--- dev-null.sh once (from the devtools).
---@param on_done? fun() called once signed in
function M.login(on_done)
	local fingerprint = ensure_key()
	if not fingerprint then
		return
	end
	local cookie = vim.trim((vim.fn.inputsecret("Cookie header for dev-null.sh: "):gsub("^%s*[Cc]ookie:%s*", "")))
	if cookie == "" then
		return
	end

	local verifier = util.base64url(util.random_bytes(32))
	local challenge = util.base64url(vim.text.hexdecode(vim.fn.sha256(verifier)))
	local code, err = authorize(cookie, {
		fingerprint = fingerprint,
		device_name = "Neovim on " .. vim.uv.os_gethostname(),
		code_challenge = challenge,
		code_challenge_method = "S256",
		state = util.hex(util.random_bytes(16)),
		redirect_uri = "devnull://neovim",
	})
	if not code then
		if err then
			util.notify(err, vim.log.levels.ERROR)
		end
		return
	end

	api.request("POST", "/api/v1/devices", { code = code, code_verifier = verifier }, function(res, e)
		if not res then
			return util.notify("could not redeem the approval: " .. e, vim.log.levels.ERROR)
		end
		local user = type(res.data) == "table" and res.data or {}
		local f = assert(io.open(M.approved_file, "w"))
		f:write(user.username or "", "\n")
		f:close()
		util.notify(("signed in as @%s"):format(user.username or "?"))
		if on_done then
			on_done()
		end
	end)
end

return M
