# Authoring tutorials

Everything a tutorial needs is data. A definition is a Lua table registered
with the engine, usually once at plugin load time:

```lua
require("tutorial").register({
  id = "my-plugin-basics",       -- unique; users run :Tutorial my-plugin-basics
  title = "Getting started",
  summary = "First steps with my plugin",  -- optional menu one-liner
  layout = "card",               -- optional: "card" (default) or "split"
  setup = function(ctx) end,     -- optional workspace prep; ctx persists
  teardown = function(ctx) end,  -- optional cleanup on quit or finish
  steps = {
    {
      id = "run-it",             -- unique within the tutorial
      title = "Run the thing",
      body = {                   -- string or list of lines
        "Press {key:<leader>x}, then save the file.",
      },
      hint = "The toolbar lives at the top.",  -- shown when the user presses h
      completion = {             -- any match completes the step...
        "on_command:MyPluginThing",
        { context = function() return vim.g.ran end },
      },                         -- ...but d always works too
    },
  },
})
```

If you would rather learn this by doing it, run `:Tutorial authoring` — the
built-in tour writes, registers, and runs a real tutorial alongside you.

## Steps

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | stable identifier; progress is keyed on it |
| `title` | yes | card heading |
| `layout` | no | `"split"` (default): steps pin in a panel beside the workspace; `"card"`: full-window stepping |
| `setup` | no | `function(ctx)` — runs once at start; `ctx` is yours (baselines, paths) |
| `teardown` | no | `function(ctx)` — runs on quit or completion |
| `summary` | no | one-liner shown in the menu |
| `steps` | yes | ordered step tables below |

Re-registering an id replaces the definition in place, which keeps its menu
position — useful while iterating.

### Steps

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | stable identifier within the tutorial |
| `title` | yes | card heading |
| `body` | yes | string or list of lines; see [Body text](#body-text) |
| `hint` | no | extra nudge revealed by `h` |
| `completion` | no | spec list below; omit for manual-only steps |

### The pinned panel

By default a running tutorial docks a panel (left, 42 columns — user-
configurable via `setup({ panel_position = ..., panel_width = ... })`) and
updates it silently as steps complete. **Focus is never taken**: write your
step bodies assuming the user is looking at their prose, not your card.
Users hide/show with `s`, or by re-running `:Tutorial`. Set
`layout = "card"` only for tutorials that must own the whole screen.

## Completion specs

Steps complete when **any** spec matches, and always via the manual `d` key,
so a tutorial can never trap a user whose environment differs from yours.

| Spec | Kind | Completes when |
| --- | --- | --- |
| `on_command:Name [args…]` | edge | an Ex command line starting with `Name` runs |
| `on_event:Pattern` | edge | a `User` autocmd fires with that pattern |
| `on_buffer:pattern` | edge | a buffer opens whose full path matches the Lua pattern |
| `on_file_exists:glob` | state | the glob expands to at least one path |
| `on_file_contains:path:pattern` | state | the readable file contains the Lua pattern |
| `{ context = fn }` | state | the predicate returns non-nil, non-false |

Notes:

- **Edge** specs are evaluated when their event fires; **state** specs are
  polled on save, buffer entry, cursor hold, and card render.
- Command matching looks at the leading command word only — trailing args are
  allowed (`on_command:echo` matches `:echo hi`).
- `on_file_contains` splits path from pattern at the *first* colon after the
  prefix; patterns are Lua patterns, not regex.
- Predicates are wrapped in `pcall`: an erroring check is false, not fatal.
- Relative `on_file_exists` / `on_file_contains` paths anchor to the working
  directory captured when the tutorial started — a `setup` that relocates the
  user cannot break them. Absolute paths pass through untouched.
- Prefer the narrowest spec that tells the truth. A step that checks real
  state teaches more than one anyone can pass blind — but keep `d` in mind as
  the universal fallback.

## Body text

Lines are strings. `{key:X}` tokens render as highlighted key hints; if `X`
contains whitespace it is treated as prose and rendered muted instead of as a
mapping name. When a mapping actually exists for `X`, the hint renders in the
"done" color — cards show your users their own keymaps, not yours.

## Progress

Sticky JSON under `stdpath("data")/tutorial/<id>.json`. Events only ever set
completion; un-completing requires `:Tutorial reset [id]`. Starting a
tutorial resumes at the first incomplete step, and a finished tutorial
refuses replay until reset.

## Checklist for a good tour

- One idea per step; teach the workflow, not the whole plugin.
- Make completions observable early — the first step should check itself off
  quickly, it sells the engine better than any prose.
- Write hints for the person who will need them at 1am, not the readme reader.
- Ship a wrap-up step pointing at further docs and how to reset/replay.
