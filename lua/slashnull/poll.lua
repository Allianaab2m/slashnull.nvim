-- Notifications, polled. Listing them marks them all read, as on the web, so
-- the list is only fetched when /me counts something unread. The ones it just
-- marked carry the read_at the response reports.

local api = require("slashnull.api")
local auth = require("slashnull.auth")
local config = require("slashnull.config")
local util = require("slashnull.util")

local M = {}

local timer = nil

local verbs = {
	followed = "followed you",
	replied = "replied to your commit",
	quoted = "quoted your commit",
	starred = "starred your commit",
	mentioned = "mentioned you",
	approved = "your commit was approved",
	rejected = "your commit was rejected",
}

--- "@foo and 2 others starred your commit". The second value is the length
--- of the leading "@foo", 0 when the line doesn't start with a user.
---@param n table one notification group of /api/v1/notifications
---@return string, integer
function M.headline(n)
	if n.type == "approved" or n.type == "rejected" then
		return verbs[n.type], 0
	end
	local actor = type(n.actor) == "table" and n.actor or {}
	local user = "@" .. (actor.username or "?")
	local who = user
	local others = (tonumber(n.actors_count) or 1) - 1
	if others > 0 then
		who = ("%s and %d other%s"):format(who, others, others == 1 and "" or "s")
	end
	return ("%s %s"):format(who, verbs[n.type] or n.type), #user
end

---@param n table one notification group of /api/v1/notifications
---@return string
local function describe(n)
	local head = M.headline(n)
	local commit = type(n.commit) == "table" and n.commit or {}
	local text = type(commit.body) == "string" and vim.trim((commit.body:gsub("%s+", " "))) or ""
	if n.type == "rejected" and type(n.reason) == "string" then
		text = "reason: " .. n.reason
	end
	if vim.fn.strchars(text) > 140 then
		text = vim.fn.strcharpart(text, 0, 140) .. "…"
	end
	return text ~= "" and (head .. "\n" .. text) or head
end

function M.stop(reason)
	if timer then
		timer:stop()
		timer:close()
		timer = nil
	end
	if reason then
		util.notify(reason, vim.log.levels.WARN)
	end
end

--- Check once.
function M.poll()
	if not auth.approved() then
		return M.stop("not logged in, run :DevNullLogin")
	end
	api.request("GET", "/api/v1/me", nil, function(me, err, code)
		if not me then
			if code == "device_not_approved" or code == "invalid_signature" then
				auth.forget()
				return M.stop(err .. " Run :DevNullLogin again.")
			end
			return util.notify("poll failed: " .. err, vim.log.levels.DEBUG)
		end
		if (tonumber(me.unread_notifications_count) or 0) == 0 then
			return
		end
		api.request("GET", "/api/v1/notifications", nil, function(list, e)
			if not list then
				return util.notify("could not load notifications: " .. e, vim.log.levels.WARN)
			end
			local fresh = vim.tbl_filter(function(n)
				return n.read_at == list.read_at
			end, type(list.data) == "table" and list.data or {})
			-- Oldest first, so the newest ends up on top of the notification stack.
			for i = #fresh, 1, -1 do
				util.notify(describe(fresh[i]))
			end
		end)
	end)
end

function M.start()
	if timer then
		return
	end
	timer = assert(vim.uv.new_timer())
	timer:start(0, config.interval * 1000, vim.schedule_wrap(M.poll))
end

return M
