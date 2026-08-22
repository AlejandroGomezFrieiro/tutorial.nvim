# Running a tutorial

Start one with `:Tutorial` (menu), `:Tutorial <id>`, or resume where you left
off — progress is sticky until you reset.

## The pinned panel

A running tutorial docks a panel beside your work (left, 42 columns by
default). Completing a step updates the panel silently: your windows, cursor,
and focus never move. You write; it keeps score.

| Key | Action |
| --- | --- |
| `n` / `p` | next / previous step (viewing only) |
| `h` | toggle the hint |
| `a` | answer the current step's question (steps with an input show `[a]nswer`) |
| `r` | re-answer: prompts again and overwrites the stored answer |
| `d` | mark this step done manually |
| `s` | hide / show the pinned panel |
| `q` | pause the tutorial (progress saved) |

Questions draw on the command line and never move your focus. Answering
stores the value for the rest of the tour — later steps can speak it back —
and survives quitting. `<Esc>` skips the question; `d` always completes the
step either way.

Re-running `:Tutorial` while active hides or restores the panel. When the
last step completes, the panel shows a completion summary until you dismiss
it with `q`.

## Configuration

```lua
require("tutorial").setup({
  panel_position = "left", -- or "right"
  panel_width = 42,
})
```

## Statusline integration

`require("tutorial").status()` returns e.g. `"Hello, tutorial.nvim 3/6"`
while a tutorial runs, and `nil` otherwise:

```lua
-- lualine-style
require("lualine").setup({
  sections = {
    lualine_x = { { require("tutorial").status, cond = require("tutorial").status } },
  },
})
```
