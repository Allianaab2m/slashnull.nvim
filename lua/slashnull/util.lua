local M = {}

M.ns = vim.api.nvim_create_namespace("slashnull")

function M.notify(msg, level)
	vim.notify("slashnull: " .. msg, level or vim.log.levels.INFO, { title = "/dev/null" })
end

function M.random_bytes(n)
	local f = assert(io.open("/dev/urandom", "rb"))
	local bytes = f:read(n)
	f:close()
	return bytes
end

function M.hex(bytes)
	return (bytes:gsub(".", function(c)
		return ("%02x"):format(c:byte())
	end))
end

function M.base64url(bytes)
	return (vim.base64.encode(bytes):gsub("[+/=]", { ["+"] = "-", ["/"] = "_", ["="] = "" }))
end

--- Unix time of an ISO 8601 Zulu timestamp as the API writes them.
local function unix_time(iso)
	local y, mo, d, h, mi, s = (iso or ""):match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
	if not y then
		return nil
	end
	-- os.time reads the table as local time; shift it back to UTC.
	local now = os.time()
	local offset = os.difftime(now, os.time(os.date("!*t", now) --[[@as osdate]]))
	return os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s, isdst = false }) + offset
end

--- "now", "5m", "3h", "2d", or the date for anything older than a week.
function M.ago(iso)
	local t = unix_time(iso)
	if not t then
		return ""
	end
	local diff = os.time() - t
	if diff < 60 then
		return "now"
	elseif diff < 3600 then
		return ("%dm"):format(diff / 60)
	elseif diff < 86400 then
		return ("%dh"):format(diff / 3600)
	elseif diff < 7 * 86400 then
		return ("%dd"):format(diff / 86400)
	end
	return os.date("%Y-%m-%d", t) --[[@as string]]
end

--- Lines of a commit body, indented under its header.
function M.body_lines(body)
	local out = {}
	for line in vim.gsplit((body or ""):gsub("\r", ""), "\n") do
		table.insert(out, "  " .. line)
	end
	return out
end

return M
