-- slashnull.nvim: /dev/null (https://dev-null.sh) from Neovim.

local config = require("slashnull.config")

local M = {}

--- Data of earlier versions, kept by the dotfiles module this grew out of.
local function migrate()
	local old = vim.fs.joinpath(vim.fn.stdpath("data"), "devnull")
	if vim.uv.fs_stat(old) and not vim.uv.fs_stat(config.data_dir) then
		vim.uv.fs_rename(old, config.data_dir)
	end
end

---@param opts? slashnull.Config
function M.setup(opts)
	config.set(opts)
	migrate()
	require("slashnull.highlight").setup()
	if config.poll and require("slashnull.auth").approved() then
		require("slashnull.poll").start()
	end
end

--- Commit `message`, or open a compose buffer when it is empty. `code` is
--- added at the end in a fence of the current filetype.
---@param message? string
---@param code? string[]
function M.commit(message, code)
	local commit = require("slashnull.commit")
	local fenced = code and commit.fenced(code) or nil
	if vim.trim(message or "") == "" then
		return commit.compose(fenced)
	end
	if fenced then
		message = message .. "\n\n" .. table.concat(fenced, "\n")
	end
	commit.commit(message)
end

---@param lines? string[]
---@param opts? slashnull.ComposeOpts
function M.compose(lines, opts)
	require("slashnull.commit").compose(lines, opts)
end

function M.login()
	require("slashnull.auth").login(function()
		if config.poll then
			local poll = require("slashnull.poll")
			poll.stop()
			poll.start()
		end
	end)
end

function M.poll()
	require("slashnull.poll").poll()
end

function M.start()
	require("slashnull.poll").start()
end

function M.stop()
	require("slashnull.poll").stop()
end

---@param log? string following, latest or trending
function M.timeline(log)
	require("slashnull.view").timeline(log)
end

function M.notifications()
	require("slashnull.view").notifications()
end

function M.open_notifications()
	vim.ui.open(config.url .. "/notifications")
end

return M
