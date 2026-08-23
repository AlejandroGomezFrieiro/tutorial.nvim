# Authoring tutorials

Everything a tutorial needs is data. A definition is a Lua table registered
with the engine, usually once at plugin load time:

```lua
require("tutorial").register({
  id = "my-plugin-basics",       -- unique; users run :Tutorial my-plugin-basics
  title = "Getting started",
  summary = "First steps with my plugin",  -- optional menu one-liner
  tags = { "getting-started" },  -- optional; shown and filterable in menus
  layout = "card",               -- optional: "card" (default) or "split"
  sections = {                   -- optional chunk headers for long tours:
    { title = "Basics", steps = { "run-it" } },  -- membership by step id
  },
  setup = function(ctx) end,     -- optional workspace prep; ctx persists
  teardown = function(ctx) end,  -- optional cleanup on quit or finish
  steps = {
    {
      id = "run-it",             -- unique within the tutorial
      title = "Run the thing",
      body = {                   -- string or list of lines
        "Press {key:<leader>x}, then save the file.",
      },
      hint = { "Rung one", "Rung two" },  -- string or ladder; h reveals one
      recall = true,             -- mask {key:…} tokens until attempted/revealed
      mistake = {                -- gentle corrections; they teach, never advance
        { match = "<F9>", message = "That key does nothing here." },
      },
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

## Linting

`require("tutorial").validate(def)` returns `(errors, warnings)` for any
definition without registering it. `register()` refuses structural errors and
surfaces warnings (unknown fields, malformed completion specs, `{answer:…}`
tokens pointing at nonexistent steps) as notifications — a typo in a shipped
tour should be visible at load time, not discovered mid-tutorial.

## Steps

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | stable identifier; progress is keyed on it |
| `title` | yes | card heading |
| `layout` | no | `"split"` (default): steps pin in a panel beside the workspace; `"card"`: full-window stepping |
| `setup` | no | `function(ctx)` — runs once at start; `ctx` is yours (baselines, paths) |
| `teardown` | no | `function(ctx)` — runs on quit or completion |
| `summary` | no | one-liner shown in the menu |
| `tags` | no | list of strings; shown in menus, matched by `/` filtering |
| `sections` | no | list of `{ title, steps = {ids…} }` — renders a chunk header above member steps |
| `steps` | yes | ordered step tables — **or** a `function(ctx) -> list`, re-evaluated on start and resume so the tour shape can follow the user's answers |

Re-registering an id replaces the definition in place, which keeps its menu
position — useful while iterating.

### Steps

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | stable identifier within the tutorial |
| `title` | yes | card heading |
| `body` | yes | string or list of lines; see [Body text](#body-text) |
| `hint` | no | string **or list** — the hint ladder: each press of `h` reveals one more rung, wrapping back to hidden |
| `recall` | no | true masks every `{key:…}` token in the body (`[hidden]`) until the user reveals with `h` — attempt before answer |
| `mistake` | no | `{ match, message }` or a list of them — when a typed command word or key sequence equals `match`, show `message` gently in the card; never advances |
| `cond` | no | `function(ctx)` — returning false skips the step entirely (not rendered, not counted) on start and resume |
| `enter` | no | `function(ctx)` — runs once, on first present of the step per session |
| `complete` | no | `function(ctx)` — runs when the step is checked off, before teardown |
| `input` | no | ask-the-user spec, see [Input steps](#input-steps) |
| `completion` | no | spec list below; omit for manual-only steps |

Mistake matching compares Ex command *words* against `match`, and key
sequences after `<…>` notation resolution — so `match = "Echo"` catches
`:Echo hi` while the completion spec watches for lowercase `:echo`.

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
| `on_command:Name!` | edge | …and the command left `v:errmsg` untouched — a clean run, not a typo |
| `on_event:Pattern` | edge | a `User` autocmd fires matching the pattern; `*` and `?` are globs (`"MyPlugin*"` matches `MyPluginSaved`) |
| `on_key:<lhs>` | edge | the user typed the sequence; notation like `<leader>x`/`<F3>` resolves against real mappings |
| `on_buffer:pattern` | edge | a buffer opens whose full path matches the Lua pattern |
| `on_buf_contains:pattern` | state | the current buffer's text matches the Lua pattern |
| `on_diagnostic:[severity]` | state | no diagnostics of severity `error`(default)/`warn`/`info`/`hint` or worse remain in the buffer |
| `on_file_exists:glob` | state | the glob expands to at least one path |
| `on_file_contains:path:pattern` | state | some path/pattern split along the colons finds a readable file whose lines match (paths may contain colons) |
| `{ context = fn }` | state | the predicate returns non-nil, non-false |

Notes:

- **Edge** specs are evaluated when their event fires; **state** specs are
  polled on save, buffer entry, cursor hold, card render — and on a timer
  when the user sets `poll_ms`, so they track reality even mid-insert.
- Command matching looks at the leading phrase; trailing args are allowed
  (`on_command:echo` matches `:echo hi`) but prefix-sharing names do not
  (`on_command:Go!`-style word boundaries are respected).
- Key observation runs through one engine-owned `vim.on_key` listener while
  a session is active; tutorials attach nothing themselves.
- `on_file_contains` splits path from pattern at each colon *outside* `{...}`
  tokens, trying splits left to right; patterns are Lua patterns, not regex.
- Predicates are wrapped in `pcall`: an erroring check is false, not fatal.
  They receive the session `ctx` as their first argument — a predicate can be
  `function(ctx) return ctx.protagonist ~= nil end`.
- Path/glob/pattern args resolve `{ctx:…}` / `{answer:…}` tokens against the
  live session (see [Body text](#body-text)). A token that cannot resolve
  makes the spec false rather than matching a literal broken path. Relative
  paths still anchor to the working directory captured at start.
- Prefer the narrowest spec that tells the truth. A step that checks real
  state teaches more than one anyone can pass blind — but keep `d` in mind as
  the universal fallback.

## Input steps

An `input` field turns a step into a question the tutorial asks its own user:

```lua
{
  id = "name-your-lead",
  title = "Name your lead",
  body = { "Your lead is {ctx:lead}." },
  input = {
    question = "Protagonist name",   -- the command-line prompt
    type = "text",                   -- or "choice" (with choices = {...})
    default = nil,                   -- optional prefilled value
    store = "lead",                  -- answer lands in ctx.lead (defaults
                                     -- to the step id) and answers[step.id]
    transform = function(v)          -- applied first
      return require("tutorial").slug(v)
    end,
    validate = function(v)           -- then checked: true passes;
      return v ~= "" or "needs a name"
    end,                             -- false/nil or an error string re-prompts
  },
  completion = { "on_file_exists:story-{ctx:lead}.md" },
}
```

Semantics:

- The prompt draws on the **command line** and never moves window focus. It
  fires once per session, engine-owned — never inside a polled predicate.
- On confirm: `transform` runs, then `validate`. Invalid answers re-prompt;
  `<Esc>` cancels and leaves the answer unset.
- Data-only definitions cannot carry functions; give them `pattern` (a Lua
  pattern the answer must match) plus an optional `message` instead.
- Answering alone does not complete the step — completion stays with the
  usual specs (or manual `d`). `d` always works, answered or not: no answer
  means the author treats it as "answered nothing".
- `[a]nswer` in the footer prompts on demand; `r` re-answers, overwriting the
  stored value (in `ctx` and on disk).

Answers persist in the progress JSON and are seeded back into `ctx` before
`setup` on resume, so a tour picks up where its user left off.

## Portable definitions (JSON)

Anything that can be expressed without executable code can ship as
`.tutorial.json` — same field names as the Lua schema, minus `setup`,
`teardown`, `cond`, `enter`, `complete`, function predicates, and input
`transform`/`validate` (use `pattern`/`message`). Bodies, hint ladders,
mistakes, sections, tags, and every string completion spec work as-is: >

    {
      "id": "basics",
      "title": "Basics",
      "tags": ["getting-started"],
      "steps": [
        { "id": "one", "title": "Read", "body": ["hello"] },
        { "id": "two", "title": "Run it",
          "completion": ["on_command:Basics"] }
      ]
    }
<
Load from disk with `require("tutorial").load_file(path)` or
`:Tutorial load <path>`; decode a string with `from_json(text)`. Files are
purity-checked on load — a definition arriving as data stays data. Lua files
loaded through the same `load_file` keep full power.

## Analytics

With `setup({ analytics = true })`, each completed step records elapsed time,
hint presses, and mistake hits into the progress file; `:Tutorial stats [id]`
renders them. Local-only by construction — useful for finding the step your
learners stall on, useless for anything else.

## Body text

Lines are strings. Two token families render specially:

- `{key:X}` renders as a highlighted key hint; if `X` contains whitespace it
  is treated as prose and rendered muted instead of as a mapping name. When a
  mapping actually exists for `X`, the hint renders in the "done" color —
  cards show your users their own keymaps, not yours. On `recall` steps every
  token renders masked (`[hidden]`) until the user reveals it with `h`.
- `{ctx:field}` and `{answer:step_id}` interpolate the session context and
  per-step answers, in `title`, `body`, and `hint` alike. Unknown fields stay
  verbatim so a copy typo is visible, never silent — and the linter flags
  `{answer:…}` tokens that point at no step id at registration time.

For paths built from answers, prefer slugging them first:
`require("tutorial").slug("Ada Lovelace!")` → `"ada-lovelace"` keeps a `:` or
space from breaking a glob. `require("tutorial").interpolate(text, ctx,
answers)` applies the same token rules anywhere else you need them.

## Progress

Sticky JSON under `stdpath("data")/tutorial/<id>.json`:

```json
{ "version": 1, "done": {"s1": 1720000000}, "answers": {"s1": "Cyrus"}, "vars": {"theme": "loss"} }
```

Completion (`done`) is write-once; only `:Tutorial reset [id]` un-completes
steps. `answers` (per-step captures) and `vars` (free-form, via
`tutorial.var()` or the state module) are re-writable and cleared by reset
too; `stats` joins them when analytics are on. `version` tags the schema for
future migrations — readers tolerate files without it. Starting a tutorial
resumes at the first incomplete step of its *resolved* step list, seeds `ctx`
from persisted answers/vars before `setup`, and a finished tour refuses
replay until reset.

## Checklist for a good tour

- One idea per step; teach the workflow, not the whole plugin.
- Make completions observable early — the first step should check itself off
  quickly, it sells the engine better than any prose.
- Write hints for the person who will need them at 1am, not the readme reader.
- Ship a wrap-up step pointing at further docs and how to reset/replay.
