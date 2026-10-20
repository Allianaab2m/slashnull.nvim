# slashnull.nvim

[/dev/null](https://dev-null.sh) from Neovim: commit, read the timeline,
reply and star, and get notifications through `vim.notify`.

- Commits go through the site's own CLI script
  (`curl -fsSL https://dev-null.sh/commit | bash`), signed with an SSH key on
  your GitHub account.
- Everything else goes through the API of the /dev/null mobile app, signed
  with a key made for this machine and approved once as a device. Nothing
  expires; revoke it in Settings → Devices on the web.

## Requirements

- Neovim 0.11+
- `curl`, `bash`, `ssh-keygen`
- An SSH key on your GitHub account, in your agent or `~/.ssh` (for commits)

## Install

lazy.nvim:

```lua
{
	"Allianaab2m/slashnull.nvim",
	event = "VeryLazy",
	opts = {},
}
```

`setup()` starts polling for notifications once you are signed in. The
commands work without it.

## Sign in

Needed for notifications, the timeline, replies from the timeline and stars.
Committing works without it.

1. Sign in on https://dev-null.sh in your browser.
2. Open the devtools, Network tab, reload, select the `dev-null.sh` request
   and copy the value of its `Cookie` request header.
3. `:DevNullLogin`, paste it, and approve the device.

The cookie is used for the approval only and is never stored.

## Commands

| Command | |
|---|---|
| `:DevNull {text}` | Commit `{text}`. With a range, the selection is added at the end in a fence of the current filetype |
| `:DevNull` | Open a compose buffer (with the selection fenced, given a range). `:w` asks, then commits |
| `:DevNullCompose` | Same as `:DevNull` without text |
| `:DevNullTimeline [following\|latest\|trending]` | The timeline, on the right |
| `:DevNullNotifications` | Notifications, on the right. Listing them marks them read |
| `:DevNullLogin` | Approve this machine as a device |
| `:DevNullPoll` / `:DevNullStop` | Check notifications now / stop polling |
| `:DevNullOpen` | Notifications in the browser |

## Keys in the timeline and notifications

| Key | |
|---|---|
| `j` / `k` | Next / previous commit or reply |
| `o`, `za` | Open / close the replies of the commit under the cursor |
| `i` | New commit |
| `r` | Reply to the commit under the cursor |
| `s` | Star / unstar |
| `<CR>` | Open in the browser |
| `R` | Reload |
| `L` | Load more |
| `]]` / `[[` | Next / previous top-level commit |
| `q` | Close |

Code blocks in commits are highlighted with Tree-sitter when a parser for
their fence language is installed.

## Options

```lua
{
	url = "https://dev-null.sh",
	interval = 60, -- seconds between notification polls
	poll = true, -- poll for notifications once signed in
	width = 60, -- columns of the timeline window
	replies = 3, -- replies shown under a commit on the timeline
	lane_colors = true, -- color usernames with the color each user picked
	fence_lang = { typescriptreact = "tsx", javascriptreact = "jsx", sh = "bash" },
}
```

## Highlights

All are linked by default and can be overridden.

| Group | Default |
|---|---|
| `SlashnullUser` | `Identifier` (usernames, when `lane_colors` is off or a user has no color) |
| `SlashnullMeta` | `Comment` |
| `SlashnullStar` | `DiagnosticWarn` |
| `SlashnullRail` | `NonText` |
| `SlashnullNotification` | `Title` |
| `SlashnullNew` | `DiagnosticInfo` |
| `SlashnullHint` | `StatusLine` |
| `SlashnullHintKey` | `Special` |
