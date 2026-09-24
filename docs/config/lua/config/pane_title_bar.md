# `pane_title_bar`

When `true`, WezTerm reserves one cell row above every pane in the active tab and draws a pane title there. The row is outside the pane's terminal viewport, so applications receive the reduced terminal height. The default is `false`.

The title defaults to the pane's terminal title. Use [format-pane-title](../window-events/format-pane-title.md) to customize it. Active and inactive titles use the corresponding tab bar colors unless the callback returns formatting items with explicit colors.

```lua
return { pane_title_bar = true }
```
