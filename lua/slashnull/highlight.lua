-- Highlight groups, all linked by default so a colorscheme or the user can
-- override any of them. Usernames take the lane color each user picked on
-- /dev/null, unless `lane_colors` is off.

local config = require("slashnull.config")

local M = {}

local links = {
	SlashnullUser = "Identifier",
	SlashnullMeta = "Comment",
	SlashnullStar = "DiagnosticWarn",
	SlashnullRail = "NonText",
	SlashnullNotification = "Title",
	SlashnullNew = "DiagnosticInfo",
	SlashnullHint = "StatusLine",
	SlashnullHintKey = "Special",
}

---@type table<string, string> lane color -> group
local lanes = {}

function M.setup()
	for group, link in pairs(links) do
		vim.api.nvim_set_hl(0, group, { link = link, default = true })
	end
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("slashnull_highlight", { clear = true }),
		callback = function()
			-- A colorscheme clears every group; lane groups come back on use.
			lanes = {}
			for group, link in pairs(links) do
				vim.api.nvim_set_hl(0, group, { link = link, default = true })
			end
		end,
	})
end

--- The group a user's name is drawn with.
---@param user table? a user of the API, with its `lane` color
---@return string
function M.user(user)
	local lane = type(user) == "table" and user.lane
	if not config.lane_colors or type(lane) ~= "string" or not lane:match("^#%x%x%x%x%x%x$") then
		return "SlashnullUser"
	end
	lane = lane:lower()
	if not lanes[lane] then
		lanes[lane] = "SlashnullLane_" .. lane:sub(2)
		vim.api.nvim_set_hl(0, lanes[lane], { fg = lane, bold = true })
	end
	return lanes[lane]
end

return M
