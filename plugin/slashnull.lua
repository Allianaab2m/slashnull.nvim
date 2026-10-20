if vim.g.loaded_slashnull then
	return
end
vim.g.loaded_slashnull = true

local command = vim.api.nvim_create_user_command

local function range_code(arg)
	if arg.range == 0 then
		return nil
	end
	return require("slashnull.commit").range_lines(arg)
end

command("DevNull", function(arg)
	require("slashnull").commit(arg.args, range_code(arg))
end, { desc = "Commit to /dev/null (no text: open a compose buffer)", nargs = "*", range = true })

command("DevNullCompose", function(arg)
	local code = range_code(arg)
	require("slashnull").compose(code and require("slashnull.commit").fenced(code) or nil)
end, { desc = "Compose a long commit to /dev/null", range = true })

command("DevNullLogin", function()
	require("slashnull").login()
end, { desc = "Approve this machine as a /dev/null device" })

command("DevNullPoll", function()
	require("slashnull").poll()
end, { desc = "Check /dev/null notifications now" })

command("DevNullStop", function()
	require("slashnull").stop()
end, { desc = "Stop polling /dev/null notifications" })

command("DevNullTimeline", function(arg)
	require("slashnull").timeline(arg.args)
end, {
	desc = "Show a /dev/null log (following, latest, trending)",
	nargs = "?",
	complete = function()
		return require("slashnull.config").logs
	end,
})

command("DevNullNotifications", function()
	require("slashnull").notifications()
end, { desc = "Show /dev/null notifications (marks them read)" })

command("DevNullOpen", function()
	require("slashnull").open_notifications()
end, { desc = "Open /dev/null notifications in the browser" })
