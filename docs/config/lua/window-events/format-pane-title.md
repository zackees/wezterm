# `format-pane-title`

This synchronous callback formats the one-row title above each pane when `pane_title_bar = true`. It receives `(pane, config, max_width)`, where `pane` is the pane's [PaneInformation](../PaneInformation.md) and `max_width` is the number of cells available in that split. Return a string or a `wezterm.format` item table. `nil` uses the terminal title. Text is clipped to the pane width.

The callback runs on the GUI thread, so keep it fast. Its result is cached per pane for up to one second; the GUI schedules a repaint when it expires. `pane.current_working_dir` and `pane.foreground_process_name` are available for directory and command labels. For Git worktrees, read the `gitdir:` target from a `.git` file before reading `HEAD`; each worktree has its own HEAD.

```lua
local wezterm = require 'wezterm'
wezterm.on('format-pane-title', function(pane, config, max_width)
  local cwd = pane.current_working_dir
  return cwd and cwd.file_path or pane.title
end)
return { pane_title_bar = true }
```
