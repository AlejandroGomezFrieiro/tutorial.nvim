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
| `h` | next hint rung — or reveal a recall step's masked keys |
| `a` | answer the current step's question (steps with an input show `[a]nswer`) |
| `r` | re-answer: prompts again and overwrites the stored answer |
| `d` | mark this step done manually |
| `s` | hide / show the pinned panel |
| `q` | pause the tutorial (progress saved) |

Hint ladders reveal one nudge per press and wrap back to hidden. Steps marked
`recall = true` hide their key tokens behind `[hidden]` until you press `h`:
try first, then look. When a step declares a mistake (say, the wrong
command), the card shows a gentle correction — it never advances for you.

Questions draw on the command line and never move your focus. Answering
stores the value for the rest of the tour — later steps can speak it back —
and survives quitting. `<Esc>` skips the question; `d` always completes the
step either way.

Re-running `:Tutorial` while active hides or restores the panel. When the
last step completes, the panel shows a completion summary until you dismiss
it with `q`.

## Commands

| Command | Action |
| --- | --- |
| `:Tutorial focus` | bring the panel/card forward deliberately |
| `:Tutorial next` / `prev` | view the next/previous step |
| `:Tutorial goto N` | jump to step N |
| `:Tutorial status` | print the statusline string |
| `:Tutorial new <id>` | scaffold `<id>.tutorial.lua` in the cwd |
| `:Tutorial load <path>` | register from `.lua` or `.tutorial.json` |
| `:Tutorial stats [id]` | per-step telemetry (needs analytics) |
| `:Tutorial reset [id]` | forget progress |

The menu supports `/` substring filtering over id/title/tags, mouse clicks,
and shows finished tours with how long ago they were completed.

## Configuration

```lua
require("tutorial").setup({
  panel_position = "left", -- or "right"
  panel_width = 42,
  poll_ms = 0,             -- >0: poll state checks on a timer while active
  analytics = false,       -- record per-step time/hints/mistakes locally
  ascii = false,           -- ASCII progress glyphs (* - x)
  glyphs = { done = "✦", pending = "✧", check = "✓" },
  highlights = {},         -- e.g. { TutorialTitle = { fg = "#ff0000" } }
})
```

Unknown options warn instead of being silently dropped.

## Statusline integration

`require("tutorial").status()` returns e.g. `"Hello, tutorial.nvim 3/6"`
while a tutorial runs, and `nil` otherwise. Variants: `status("percent")` →
`"Hello, tutorial.nvim 50%"`, `status("step")` → appends the current step
title:

```lua
-- lualine-style
require("lualine").setup({
  sections = {
    lualine_x = { { require("tutorial").status, cond = require("tutorial").status } },
  },
})
```
