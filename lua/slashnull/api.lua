-- Requests to the API of the /dev/null mobile app, signed with the device
-- key: the key signs "<timestamp>\n<nonce>\n<METHOD>\n<path and query>\n<body>"
-- in the devnull-api namespace, sent along in the X-Devnull-Timestamp,
-- X-Devnull-Nonce and X-SSH-Signature headers.

local config = require("slashnull.config")
local util = require("slashnull.util")

local M = {}

M.key_file = vim.fs.joinpath(config.data_dir, "id_ed25519")

---@param method string
---@param path string path and query, e.g. /api/v1/me
---@param body? table sent as JSON
---@param cb fun(res: table?, err: string?, code: string?) `code` is the API error code
function M.request(method, path, body, cb)
	local done = vim.schedule_wrap(cb)
	local json = body and vim.json.encode(body) or ""
	local timestamp = tostring(os.time())
	local nonce = util.hex(util.random_bytes(16))
	local message = table.concat({ timestamp, nonce, method, path, json }, "\n")

	vim.system({ "ssh-keygen", "-Y", "sign", "-n", "devnull-api", "-f", M.key_file }, { stdin = message, text = true }, function(sig)
		if sig.code ~= 0 then
			return done(nil, "could not sign: " .. vim.trim(sig.stderr))
		end
		local signature = sig.stdout:gsub("%-%-%-%-%-[^\n]*", ""):gsub("%s+", "")

		local cmd = {
			"curl",
			"--disable",
			"--silent",
			"--show-error",
			"--proto",
			"=https",
			"--max-time",
			"20",
			"--request",
			method,
			"--header",
			"Accept: application/json",
			"--header",
			"X-Devnull-Timestamp: " .. timestamp,
			"--header",
			"X-Devnull-Nonce: " .. nonce,
			"--header",
			"X-SSH-Signature: " .. signature,
			"--write-out",
			"\n%{http_code}",
		}
		if body then
			vim.list_extend(cmd, { "--header", "Content-Type: application/json", "--data-binary", "@-" })
		end
		table.insert(cmd, config.url .. path)

		vim.system(cmd, { stdin = body and json or nil, text = true }, function(out)
			if out.code ~= 0 then
				return done(nil, vim.trim(out.stderr))
			end
			local raw, status = out.stdout:match("^(.*)\n(%d+)$")
			local ok, res = pcall(vim.json.decode, raw or "")
			res = ok and type(res) == "table" and res or {}
			if not status or not status:match("^2") then
				return done(nil, res.message or ("HTTP " .. tostring(status)), res.code)
			end
			done(res)
		end)
	end)
end

return M
