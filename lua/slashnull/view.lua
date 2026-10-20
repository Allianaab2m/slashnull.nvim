-- The timeline and the notifications in a buffer, on the right.

local api = require("slashnull.api")
local commit = require("slashnull.commit")
local config = require("slashnull.config")
local hl = require("slashnull.highlight")
local poll = require("slashnull.poll")
local util = require("slashnull.util")

local M = {}

---@class slashnull.View
---@field kind "log"|"notifications"
---@field log? string
---@field items table[]
---@field read_at? string when the notifications were marked read
---@field cursor? string next page, nil when there is none
---@field owners table[] what each line belongs to: an item, or a reply shown under it
---@field heads integer[] first line of each item and each reply, in order

---@type table<integer, slashnull.View>
local views = {}

---@class slashnull.CodeBlock
---@field row integer buffer row (0-based) of its first line of code
---@field col integer bytes of indent and rails before the code
---@field lang string fence language
---@field code string[]

--- Fenced code found while rendering, highlighted once the lines are set.
---@type slashnull.CodeBlock[]
local blocks = {}

--- Add the lines of a commit body under `prefix`, and note its fenced code
--- blocks for Tree-sitter.
local function push_body(body, prefix, lines, marks)
	local fence, block
	for _, line in ipairs(util.body_lines(body)) do
		line = line:sub(3) -- body_lines indents by two; the prefix does that here
		table.insert(lines, prefix .. "  " .. line)
		local row = #lines - 1
		if not fence then
			local ticks, lang = line:match("^%s*(```+)%s*([%w_+#.-]*)")
			if ticks then
				fence = ticks
				block = { row = row + 1, col = #prefix + 2, lang = lang, code = {} }
				table.insert(marks, { row, 0, -1, "SlashnullMeta" })
			end
		elseif line:match("^%s*" .. fence .. "`*%s*$") then
			table.insert(marks, { row, 0, -1, "SlashnullMeta" })
			if block.lang ~= "" and #block.code > 0 then
				table.insert(blocks, block)
			end
			fence, block = nil, nil
		else
			table.insert(block.code, line)
		end
	end
end

--- "@user  Name  ☆2  ↩1  5m  abc1234", with its highlights.
local function commit_header(c, indent, lines, marks)
	local author = type(c.author) == "table" and c.author or {}
	local row = #lines
	local user = indent .. "@" .. (author.username or "?")
	local name = type(author.name) == "string" and author.name ~= "" and ("  " .. author.name) or ""
	local stars = ("%s%d"):format(c.starred and "★" or "☆", tonumber(c.stars_count) or 0)
	local meta = ("  %s  ↩%d  %s  %s"):format(stars, tonumber(c.replies_count) or 0, util.ago(c.created_at), c.short_hash or "")
	table.insert(lines, user .. name .. meta)
	table.insert(marks, { row, #indent, #user, hl.user(author) })
	table.insert(marks, { row, #user, -1, "SlashnullMeta" })
	if c.starred then
		local col = #user + #name + 2
		table.insert(marks, { row, col, col + #"★", "SlashnullStar" })
	end
end

--- The replies of `c` on a rail, one more rail per level, and under them how
--- many are left to open with `o`. The lines of each reply belong to it, so
--- r, s, o and <CR> act on the reply under the cursor.
local function render_replies(c, depth, lines, marks, owners, heads)
	local rail = "  " .. ("│ "):rep(depth)
	local replies = c.replies or {}
	for _, reply in ipairs(replies) do
		local first = #lines + 1
		table.insert(heads, first)
		commit_header(reply, rail, lines, marks)
		push_body(reply.body, rail, lines, marks)
		for row = first, #lines do
			owners[row] = reply
			table.insert(marks, { row - 1, 0, #rail, "SlashnullRail" })
		end
		render_replies(reply, depth + 1, lines, marks, owners, heads)
	end
	local rest = (tonumber(c.replies_count) or 0) - #replies
	if rest > 0 then
		local count = #replies > 0 and ("%d more"):format(rest) or ("%d repl%s"):format(rest, rest == 1 and "y" or "ies")
		table.insert(lines, ("  %s└ %s (o)"):format(("│ "):rep(depth - 1), count))
		owners[#lines] = c
		table.insert(marks, { #lines - 1, 0, -1, "SlashnullMeta" })
	end
end

local function render_commit(c, lines, marks, owners, heads)
	commit_header(c, "", lines, marks)
	if c.parent_id ~= nil and c.parent_id ~= vim.NIL then
		table.insert(lines, "  ↳ reply")
		table.insert(marks, { #lines - 1, 0, -1, "SlashnullMeta" })
	end
	push_body(c.body, "", lines, marks)
	local images = type(c.images) == "table" and #c.images or 0
	if images > 0 then
		table.insert(lines, ("  [%d image%s]"):format(images, images == 1 and "" or "s"))
		table.insert(marks, { #lines - 1, 0, -1, "SlashnullMeta" })
	end
	local quoted = type(c.quoted_commit) == "table" and c.quoted_commit or nil
	if quoted then
		local qa = type(quoted.author) == "table" and quoted.author.username or "?"
		local first = vim.split(quoted.body or "", "\n")[1]
		table.insert(lines, ("  ┃ @%s: %s"):format(qa, first))
		table.insert(marks, { #lines - 1, 0, -1, "SlashnullMeta" })
	end

	render_replies(c, 1, lines, marks, owners, heads)
end

local function render_notification(n, view, lines, marks)
	local row = #lines
	local new = n.read_at == view.read_at
	local prefix = new and "● " or "  "
	local headline, user_len = poll.headline(n)
	local head = prefix .. headline
	local meta = "  " .. util.ago(n.created_at)
	-- Known once starred from here.
	local c = type(n.commit) == "table" and n.commit or {}
	if c.starred ~= nil and c.starred ~= vim.NIL then
		meta = ("  %s%d%s"):format(c.starred and "★" or "☆", tonumber(c.stars_count) or 0, meta)
	end
	table.insert(lines, head .. meta)
	table.insert(marks, { row, 0, #head, "SlashnullNotification" })
	table.insert(marks, { row, #head, -1, "SlashnullMeta" })
	if user_len > 0 then
		table.insert(marks, { row, #prefix, #prefix + user_len, hl.user(n.actor) })
	end
	if c.starred == true then
		table.insert(marks, { row, #head + 2, #head + 2 + #"★", "SlashnullStar" })
	end
	if new then
		table.insert(marks, { row, 0, #"●", "SlashnullNew" })
	end
	if type(n.commit) == "table" and n.type ~= "followed" then
		push_body(n.commit.body, "", lines, marks)
	end
	if n.type == "rejected" and type(n.reason) == "string" then
		table.insert(lines, "  reason: " .. n.reason)
	end
end

--- The Tree-sitter language of a fence name: a filetype ("typescript"), a
--- parser name, or a file extension ("ts").
---@return string?
local function fence_parser(name)
	local candidates = { vim.treesitter.language.get_lang(name) or name }
	local ft = vim.filetype.match({ filename = "fence." .. name })
	if ft then
		table.insert(candidates, vim.treesitter.language.get_lang(ft) or ft)
	end
	for _, lang in ipairs(candidates) do
		if pcall(vim.treesitter.language.add, lang) then
			return lang
		end
	end
end

--- Highlight a code block with its language's Tree-sitter queries, injections
--- included, shifted to where the block sits in the buffer.
---@param buf integer
---@param block slashnull.CodeBlock
local function highlight_code(buf, block)
	local lang = fence_parser(block.lang)
	if not lang then
		return
	end
	local source = table.concat(block.code, "\n")
	local ok, parser = pcall(vim.treesitter.get_string_parser, source, lang)
	if not ok then
		return
	end
	parser:parse(true)
	parser:for_each_tree(function(tree, ltree)
		local query = vim.treesitter.query.get(ltree:lang(), "highlights")
		if not query then
			return
		end
		for id, node in query:iter_captures(tree:root(), source) do
			local name = query.captures[id]
			if not vim.startswith(name, "_") and name ~= "spell" and name ~= "nospell" and name ~= "conceal" then
				local sr, sc, er, ec = node:range()
				pcall(vim.api.nvim_buf_set_extmark, buf, util.ns, block.row + sr, block.col + sc, {
					end_row = block.row + er,
					end_col = block.col + ec,
					hl_group = "@" .. name .. "." .. ltree:lang(),
					priority = vim.hl.priorities.treesitter,
				})
			end
		end
	end)
end

local function render(buf)
	local view = views[buf]
	local lines, marks, owners, heads = {}, {}, {}, {}
	blocks = {}
	for _, item in ipairs(view.items) do
		local first = #lines + 1
		table.insert(heads, first)
		if view.kind == "log" then
			render_commit(item, lines, marks, owners, heads)
		else
			render_notification(item, view, lines, marks)
		end
		table.insert(lines, "")
		for row = first, #lines do
			owners[row] = owners[row] or item
		end
	end
	view.owners, view.heads = owners, heads
	if #view.items == 0 then
		table.insert(lines, view.kind == "log" and "Nothing here yet." or "No notifications.")
	elseif view.cursor then
		table.insert(lines, "-- L: load more --")
		table.insert(marks, { #lines - 1, 0, -1, "SlashnullMeta" })
	end
	-- Room for the key hints that cover the last line of the window.
	table.insert(lines, "")

	-- Keep the cursor on the same line when replies arrive and re-render.
	local win = vim.fn.bufwinid(buf)
	local cursor = win ~= -1 and vim.api.nvim_win_get_cursor(win) or nil
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	if cursor then
		pcall(vim.api.nvim_win_set_cursor, win, cursor)
	end
	vim.api.nvim_buf_clear_namespace(buf, util.ns, 0, -1)
	for _, m in ipairs(marks) do
		local end_col = m[3] == -1 and #lines[m[1] + 1] or m[3]
		vim.api.nvim_buf_set_extmark(buf, util.ns, m[1], m[2], { end_col = end_col, hl_group = m[4] })
	end
	for _, block in ipairs(blocks) do
		highlight_code(buf, block)
	end
end

--- The item, or reply, under the cursor.
local function item_at_cursor(buf)
	return views[buf].owners[vim.api.nvim_win_get_cursor(0)[1]]
end

--- The commit an item is about: the item itself on the timeline, the commit
--- a notification points to otherwise.
local function commit_of(buf, item)
	if views[buf].kind == "log" then
		return item
	end
	return type(item.commit) == "table" and item.commit or nil
end

-- Notifications whose commit someone else wrote; the others point at one of
-- your own commits.
local from_others = { replied = true, quoted = true, mentioned = true }

--- The commit under the cursor that can be replied to or starred.
local function theirs(buf, item)
	if not item then
		return nil
	end
	if views[buf].kind == "notifications" and not from_others[item.type] then
		return nil
	end
	return commit_of(buf, item)
end

--- Start each commit with the replies its preview carries, and fetch the
--- rest when the preview has fewer than `replies` of them.
local function load_replies(buf, commits)
	for _, c in ipairs(commits) do
		local preview = type(c.reply_preview) == "table" and c.reply_preview.data or {}
		c.replies = vim.list_slice(type(preview) == "table" and preview or {}, 1, config.replies)
		local count = tonumber(c.replies_count) or 0
		if #c.replies < math.min(count, config.replies) then
			api.request("GET", ("/api/v1/commits/%s/replies"):format(c.id), nil, function(res)
				if res and type(res.data) == "table" and vim.api.nvim_buf_is_valid(buf) and views[buf] then
					c.replies = vim.list_slice(res.data, 1, config.replies)
					render(buf)
				end
			end)
		end
	end
end

---@param buf integer
---@param more? boolean append the next page instead of reloading
local function load(buf, more)
	local view = views[buf]
	if more and not view.cursor then
		return
	end
	local path = view.kind == "log" and ("/api/v1/log/" .. view.log) or "/api/v1/notifications"
	if more then
		path = path .. "?cursor=" .. vim.uri_encode(view.cursor, "rfc3986")
	end
	api.request("GET", path, nil, function(res, err)
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		if not res then
			return util.notify(err, vim.log.levels.ERROR)
		end
		local data = type(res.data) == "table" and res.data or {}
		if more then
			vim.list_extend(view.items, data)
		else
			view.items = data
			-- Listing marks every notification read; the ones it just
			-- marked are the new ones, as on the web.
			view.read_at = res.read_at
		end
		local meta = type(res.meta) == "table" and res.meta or {}
		view.cursor = type(meta.next_cursor) == "string" and meta.next_cursor or nil
		if view.kind == "log" then
			load_replies(buf, data)
		end
		render(buf)
	end)
end

local function toggle_star(buf)
	local c = theirs(buf, item_at_cursor(buf))
	if not c then
		return
	end
	-- A notification's commit doesn't say whether it is starred, so the
	-- first press there stars it.
	local method = c.starred and "DELETE" or "POST"
	api.request(method, ("/api/v1/commits/%s/star"):format(c.id), nil, function(res, err)
		if not res then
			return util.notify(err, vim.log.levels.ERROR)
		end
		local updated = type(res.data) == "table" and res.data or {}
		c.starred = updated.starred
		c.stars_count = updated.stars_count
		if vim.api.nvim_buf_is_valid(buf) then
			render(buf)
		end
	end)
end

--- Open or close the replies of the commit under the cursor, like a fold.
--- Opening lists all its direct replies; closing goes back to the preview a
--- timeline commit starts with.
local function toggle_replies(buf)
	local c = views[buf].kind == "log" and item_at_cursor(buf)
	if not c then
		return
	end
	if c.expanded then
		c.expanded = false
		c.replies = c.preview or {}
		return render(buf)
	end
	if (tonumber(c.replies_count) or 0) == 0 then
		return
	end
	api.request("GET", ("/api/v1/commits/%s/replies"):format(c.id), nil, function(res, err)
		if not res then
			return util.notify(err, vim.log.levels.ERROR)
		end
		if c.preview == nil then
			c.preview = c.replies or {}
		end
		c.replies = type(res.data) == "table" and res.data or {}
		c.expanded = true
		if vim.api.nvim_buf_is_valid(buf) and views[buf] then
			render(buf)
		end
	end)
end

--- Move to the next (dir 1) or previous (dir -1) commit or reply, count times.
local function jump(buf, dir)
	local heads = views[buf].heads or {}
	local row = vim.api.nvim_win_get_cursor(0)[1]
	for _ = 1, vim.v.count1 do
		local target
		if dir > 0 then
			for _, h in ipairs(heads) do
				if h > row then
					target = h
					break
				end
			end
		else
			for i = #heads, 1, -1 do
				if heads[i] < row then
					target = heads[i]
					break
				end
			end
		end
		if not target then
			break
		end
		row = target
	end
	vim.api.nvim_win_set_cursor(0, { row, 0 })
end

local hints = {
	log = { { "jk", "move" }, { "o", "thread" }, { "i", "new" }, { "r", "reply" }, { "s", "star" }, { "⏎", "open" }, { "R", "reload" }, { "L", "more" }, { "q", "quit" } },
	notifications = { { "jk", "move" }, { "i", "new" }, { "r", "reply" }, { "s", "star" }, { "⏎", "open" }, { "R", "reload" }, { "L", "more" }, { "q", "quit" } },
}

--- The keys of a view, in a footer floating over the bottom of its window.
--- It follows the window when it is resized and goes away with it.
local function show_hints(win, kind)
	local text, marks = "", {}
	for _, h in ipairs(hints[kind]) do
		text = text .. " "
		table.insert(marks, { #text, #text + #h[1] })
		text = text .. h[1] .. " " .. h[2] .. " "
	end
	local hbuf = vim.api.nvim_create_buf(false, true)
	vim.bo[hbuf].bufhidden = "wipe"
	vim.api.nvim_buf_set_lines(hbuf, 0, -1, false, { text })
	for _, m in ipairs(marks) do
		vim.api.nvim_buf_set_extmark(hbuf, util.ns, 0, m[1], { end_col = m[2], hl_group = "SlashnullHintKey" })
	end

	local float
	local function place()
		if not vim.api.nvim_win_is_valid(win) then
			return
		end
		local width = vim.api.nvim_win_get_width(win)
		local height = math.ceil(vim.fn.strdisplaywidth(text) / width)
		local win_config = {
			relative = "win",
			win = win,
			row = vim.api.nvim_win_get_height(win) - height,
			col = 0,
			width = width,
			height = height,
			focusable = false,
			style = "minimal",
			zindex = 40,
		}
		if float and vim.api.nvim_win_is_valid(float) then
			vim.api.nvim_win_set_config(float, win_config)
		else
			float = vim.api.nvim_open_win(hbuf, false, win_config)
			vim.wo[float].wrap = true
			vim.wo[float].winhighlight = "Normal:SlashnullHint"
		end
		-- Keep the cursor out from under the footer.
		vim.wo[win].scrolloff = height
	end
	place()

	local group = vim.api.nvim_create_augroup("slashnull_hints_" .. win, { clear = true })
	vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, { group = group, callback = place })
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		pattern = tostring(win),
		callback = function()
			if float and vim.api.nvim_win_is_valid(float) then
				vim.api.nvim_win_close(float, true)
			end
			vim.api.nvim_del_augroup_by_id(group)
		end,
	})
end

---@param name string buffer name
---@param view slashnull.View
local function open(name, view)
	local buf = vim.fn.bufnr(name)
	if buf == -1 then
		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf, name)
		vim.bo[buf].bufhidden = "hide"
		vim.bo[buf].filetype = "slashnull"
		vim.bo[buf].modifiable = false
		vim.b[buf].slashnull_view = true
		views[buf] = view
		view.items, view.owners = {}, {}

		local function map(lhs, fn, desc)
			vim.keymap.set("n", lhs, function()
				fn(buf)
			end, { buffer = buf, desc = "slashnull: " .. desc, nowait = true })
		end
		local function reload_later(b)
			return function()
				-- Give the new commit a moment to show up in the log.
				vim.defer_fn(function()
					if vim.api.nvim_buf_is_valid(b) and views[b] then
						load(b)
					end
				end, 1000)
			end
		end
		map("i", function(b)
			commit.compose(nil, { on_sent = reload_later(b) })
		end, "new commit")
		map("r", function(b)
			local c = theirs(b, item_at_cursor(b))
			if not (c and c.short_hash) then
				return
			end
			local author = type(c.author) == "table" and c.author.username or "?"
			commit.compose(nil, {
				reply_to = c.short_hash,
				context = ("↳ @%s: %s"):format(author, vim.split(c.body or "", "\n")[1]),
				on_sent = reload_later(b),
			})
		end, "reply")
		map("<CR>", function(b)
			local item = item_at_cursor(b)
			local c = item and commit_of(b, item)
			local url = c and c.html_url or (item and type(item.actor) == "table" and item.actor.html_url)
			if url then
				vim.ui.open(url)
			end
		end, "open in the browser")
		map("s", toggle_star, "star / unstar")
		map("o", toggle_replies, "open / close replies")
		map("za", toggle_replies, "open / close replies")
		map("R", load, "reload")
		map("L", function(b)
			load(b, true)
		end, "load more")
		map("j", function(b)
			jump(b, 1)
		end, "next commit or reply")
		map("k", function(b)
			jump(b, -1)
		end, "previous commit or reply")
		map("]]", function()
			vim.fn.search([[^\S]], "W")
		end, "next commit")
		map("[[", function()
			vim.fn.search([[^\S]], "bW")
		end, "previous commit")
		map("q", function()
			if #vim.api.nvim_list_wins() > 1 then
				vim.cmd.close()
			else
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end, "close")
		vim.api.nvim_create_autocmd("BufWipeout", {
			buffer = buf,
			callback = function()
				views[buf] = nil
			end,
		})
	end

	local win = vim.fn.bufwinid(buf)
	if win ~= -1 then
		vim.api.nvim_set_current_win(win)
	else
		vim.cmd("botright vsplit")
		vim.api.nvim_win_set_buf(0, buf)
		vim.api.nvim_win_set_width(0, math.min(config.width, math.floor(vim.o.columns / 2)))
		show_hints(vim.api.nvim_get_current_win(), view.kind)
	end
	vim.wo.wrap = true
	vim.wo.linebreak = true
	vim.wo.breakindent = true
	vim.wo.number = false
	vim.wo.relativenumber = false
	vim.wo.signcolumn = "no"
	load(buf)
end

---@param log? string following, latest or trending
function M.timeline(log)
	log = (log and log ~= "") and log or "following"
	if not vim.tbl_contains(config.logs, log) then
		return util.notify("no such log: " .. log, vim.log.levels.ERROR)
	end
	open("slashnull://log/" .. log, { kind = "log", log = log })
end

function M.notifications()
	open("slashnull://notifications", { kind = "notifications" })
end

return M
