---@class slashnull.Config
---@field url string the /dev/null instance
---@field interval integer seconds between notification polls
---@field poll boolean poll for notifications once signed in
---@field width integer columns of the timeline and notifications window
---@field replies integer replies shown under a commit on the timeline
---@field lane_colors boolean color usernames with the lane color each user picked
---@field fence_lang table<string, string> fence names that differ from the filetype

local M = {}

---@type slashnull.Config
M.defaults = {
	url = "https://dev-null.sh",
	interval = 60,
	poll = true,
	width = 60,
	replies = 3,
	lane_colors = true,
	fence_lang = {
		typescriptreact = "tsx",
		javascriptreact = "jsx",
		sh = "bash",
	},
}

---@type slashnull.Config
M.options = vim.deepcopy(M.defaults)

M.logs = { "following", "latest", "trending" }

M.data_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "slashnull")

---@param opts? table
function M.set(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return setmetatable(M, {
	__index = function(_, key)
		return M.options[key]
	end,
})
