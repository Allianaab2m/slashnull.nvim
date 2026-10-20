-- Commits go through the site's own CLI script (`curl .../commit | bash`),
-- which signs the message with an SSH key on the GitHub account.

local config = require("slashnull.config")
local util = require("slashnull.util")

local M = {}

--- Text of the range a command was called with. A charwise visual selection
--- keeps its columns; anything else is taken line by line.
---@param arg table user command argument
---@return string[]
function M.range_lines(arg)
	local vs, ve = vim.fn.getpos("'<"), vim.fn.getpos("'>")
	if arg.range == 2 and vs[2] == arg.line1 and ve[2] == arg.line2 then
		return vim.fn.getregion(vs, ve, { type = vim.fn.visualmode() })
	end
	return vim.api.nvim_buf_get_lines(0, arg.line1 - 1, arg.line2, false)
end

--- The lines wrapped in a fence of the current filetype, long enough not to
--- be closed by a fence inside the code.
---@param lines string[]
---@return string[]
function M.fenced(lines)
	local ft = vim.bo.filetype
	local longest = 2
	for _, line in ipairs(lines) do
		local ticks = line:match("^%s*(`+)")
		if ticks and #ticks > longest then
			longest = #ticks
		end
	end
	local fence = ("`"):rep(longest + 1)
	local out = { fence .. (config.fence_lang[ft] or ft) }
	vim.list_extend(out, lines)
	table.insert(out, fence)
	return out
end

---@param message string
---@param on_done? fun(ok: boolean)
---@param reply_to? string hash of the commit replied to
function M.commit(message, on_done, reply_to)
	local cmd = {
		"bash",
		"-c",
		'set -o pipefail; url=$1; shift; curl -fsSL "$url/commit" | bash -s -- "$@"',
		"slashnull",
		config.url,
	}
	if reply_to then
		vim.list_extend(cmd, { "--reply", reply_to })
	end
	-- `--` keeps a message that starts with --reply or --image a message.
	vim.list_extend(cmd, { "--", message })
	util.notify(reply_to and ("replying to %s…"):format(reply_to) or "committing…")
	vim.system(cmd, { text = true }, function(out)
		vim.schedule(function()
			local ok = out.code == 0
			local detail = vim.trim(ok and out.stdout or (out.stderr ~= "" and out.stderr or out.stdout))
			util.notify(detail ~= "" and detail or (ok and "committed" or "commit failed"), ok and vim.log.levels.INFO or vim.log.levels.ERROR)
			if on_done then
				on_done(ok)
			end
		end)
	end)
end

---@class slashnull.ComposeOpts
---@field reply_to? string hash of the commit replied to
---@field context? string shown above the text, e.g. the commit replied to
---@field on_sent? fun() called once the commit went through

--- Open a scratch buffer for a long commit. `:w` asks before sending.
---@param lines? string[] initial body
---@param opts? slashnull.ComposeOpts
function M.compose(lines, opts)
	opts = opts or {}
	local reply_to = opts.reply_to
	-- From the timeline, split its own window so the compose stays in that
	-- column; from anywhere else, take the bottom of the screen.
	vim.cmd(vim.b.slashnull_view and "belowright 10new" or "botright 15new")
	local buf = vim.api.nvim_get_current_buf()
	local kind = reply_to and ("reply/" .. reply_to) or "compose"
	vim.api.nvim_buf_set_name(buf, ("slashnull://%s/%d"):format(kind, buf))
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "markdown"

	if lines and #lines > 0 then
		-- Leave the first lines empty for the text that goes above the code.
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.list_extend({ "", "" }, lines))
		vim.bo[buf].modified = false
	end
	if opts.context then
		vim.api.nvim_buf_set_extmark(buf, util.ns, 0, 0, {
			virt_lines = { { { opts.context, "SlashnullMeta" } } },
			virt_lines_above = true,
		})
		vim.fn.winrestview({ topfill = 1 })
	end
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	vim.cmd.startinsert()

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			local body = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
			if body == "" then
				util.notify("aborting commit due to empty commit message", vim.log.levels.WARN)
				return
			end
			local question = reply_to and ("Reply to %s?"):format(reply_to) or "Commit to /dev/null?"
			if vim.fn.confirm(question .. "\n\n" .. body, "&Yes\n&No", 2) ~= 1 then
				return
			end
			-- Clear 'modified' now so :wq can close the window; a failed
			-- commit brings the text back in a new compose buffer.
			vim.bo[buf].modified = false
			M.commit(body, function(ok)
				if ok then
					if vim.api.nvim_buf_is_valid(buf) then
						vim.api.nvim_buf_delete(buf, { force = true })
					end
					if opts.on_sent then
						opts.on_sent()
					end
				elseif not vim.api.nvim_buf_is_valid(buf) then
					M.compose(vim.split(body, "\n"), opts)
				else
					vim.bo[buf].modified = true
				end
			end, reply_to)
		end,
	})
end

return M
