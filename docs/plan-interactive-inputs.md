# Plan: Interactive & adaptive walkthroughs (input steps)

> Status: **implemented** (2026-08-22). Grows the engine so a tutorial can
> *ask* the user for its own content and then adapt — copy, completion checks,
> scaffolding, and branching all keyed off what the user typed. Written
> against the tree as of 2026-08-22; line numbers were pointers, not anchors.

## Why this exists

tutorial.nvim is declarative, event-driven, and resumable — ideal for
"perform this action and I will check it off". It cannot, however, **ask the
user anything**:

- `body`, `title`, and `hint` are static strings; the only token the
  renderer understands is `{key:X}` (`ui/step.lua:20`).
- A step is inert data (`{id,title,body,hint,completion}`); nothing runs on
  entry or on completion except the whole-tutorial `setup`/`teardown`
  (`engine.lua::present`, `engine.lua::finish_step`).
- Completion specs are a closed set of six (`checks.lua:23`), all oriented
  around *observing the editor*, not *asking its user*.
- `ctx` is a fresh `{}` created in `M.start` (`engine.lua:189`) and is never
  written to disk; the progress file stores only
  `{ done = { [step_id] = os.time() } }` (`state.lua:5`, `state.lua:41`).

### The case that triggered this

A guided-writing tutorial (storyteller.nvim) wants the learner to write a
*story of their own* — their premise, character names, places, POV. It must
not push pre-defined names or plot points at them, but there is currently no
first-class way for a step to query the user and then use the answer:

- **Ask**: no input step type; calling `vim.fn.input()` inside a
  `{ context = fn }` predicate re-fires on every hub poll (BufEnter /
  CursorHold / save / card-render), so once-only capture is impossible without
  side effects.
- **Store**: `ctx` is not persisted, so the answer dies on `q` / resume.
- **Reuse**: `{ctx:...}` interpolation does not exist, so copy cannot echo
  the user's own names back, and file/completion-check paths cannot reference
  them.
- **Branch & verify**: `finish_step` always advances linearly and steps cannot
  be skipped or re-answered, so "if you chose premise A, do the flashback
  exercise, else the item exercise" cannot fork.

This plan closes that loop — **ask → store → reuse → branch & verify** —
while preserving the engine's existing guarantees.

## Constraints to respect

The principles in `docs/design.md` and the architecture notes in `AGENTS.md`
constrain any extension:

- **Calm / focus belongs to the user.** Input must not steal focus. The least
  intrusive surface is the command line (`vim.fn.input({ prompt })`), matching
  the panel's "pin beside your work" philosophy. A floating dialog is an
  option but is extra chrome; prefer the command line first.
- **Never trap the user.** Manual `d` must work on every step. An input step
  is therefore skippable: no answer ⇒ `d` completes it and proceeds, with the
  answer left nil (authors treat nil as "answered nothing").
- **One hub.** No per-tutorial autocmds. Capture-once is a deliberate,
  engine-owned action — never a side effect inside a polled predicate.
- **Declarative first.** Steps stay data. New capabilities arrive as optional
  step *fields* (`input`, `enter`, `complete`, `cond`) rather than step types
  that fork the flow.
- **Sticky progress stays write-once**, but answers need their own re-writable
  store; only `reset` clears them.

## Missing features (verified against the code)

### Ask — a first-class input step

Steps are data. Capturing requires `vim.fn.input()`/`vim.ui.input()` inside a
`{ context = fn }` predicate, which the hub polls on BufEnter/CursorHold/save/
card-render — so the prompt refires on every poll, and there is no
capture-once guard or safe place to keep the result.

Proposed:

```lua
{
  id = "name-your-lead",
  title = "Name your lead",
  body = "What is your protagonist called?",
  input = {
    question = "Protagonist name",
    type = "text",            -- or "choice"
    choices = nil,            -- for type="choice"
    default = nil,            -- optional prefilled value
    store = "protagonist",    -- ctx.protagonist + answers[step.id]
    validate = function(v) return v ~= "" end,  -- -> err string | nil/false
    transform = function(v) return v:gsub("%s+", " "):gsub("^%s+", "") end,
  },
  completion = {
    { context = function() return ctx_protagonist_scaffolded() end },
  },
}
```

Semantics:

- Presented once per session (guard in the engine, not a predicate).
- On confirm: `transform` runs, then `validate`; invalid ⇒ re-prompt (user may
  cancel to skip). On valid: store to `ctx[store]` and to `answers[step.id]`.
- `d` always completes and leaves the answer nil — never trap.
- `r` re-prompts on an already-answered step (re-answer), overwriting the
  stored value.

### Store — answers survive quit/resume

`ctx` is `{}` at every `M.start` (`engine.lua:189`); the progress file has
only `done` (`state.lua:41`). Re-hydrating from files in `setup` is a fragile
convention, and pure-answer values (POV, premise, tone) have no file to read.

Proposed — extend the JSON and load it into `ctx` at start:

```json
{ "done": {"s1": 1720000000}, "answers": {"s1": "Cyrus"}, "vars": {"theme": "loss"} }
```

New `state` API: `set_answer(id, step_id, value)`, `answer(id, step_id)`,
`set_var(id, key, value)`, `get_var(id, key)`. `M.start` seeds `session.ctx`
from `answers`/`vars` *before* `setup` so a `setup`/`enter` can rely on prior
answers.

### Reuse — interpolate user answers into copy and checks

`key_segments` (`ui/step.lua:20`) understands only `{key:X}`. There is no way
to write "Welcome, Cyrus" or "open `references/characters/<your name>.md`".

Proposed:

- Add `{ctx:field}` (and `{answer:step_id}`) tokens, resolved from
  `session.ctx`, usable in `title`, `body`, and `hint`. When `field` is
  unknown, leave the token verbatim so a copy typo is visible, never silent.
- Resolve the same tokens in completion spec *args* (path/glob/pattern) in
  `checks.lua` before `anchored`/`expand`. This lets an author write
  `on_file_exists:references/characters/{ctx:protagonist_slug}.md`.
- Add a safe-slug/token helper so a `:` or whitespace in a name cannot break a
  path or YAML. `transform` on the input step is the author's hook; a built-in
  `tutorial.slug()` is the convenient default for paths.

### Branch & verify — adapt the route to the user's answers

`finish_step` advances to the next incomplete step in order; `goto_step(±1)`
is linear (`engine.lua:55`, `engine.lua:256`). Choice-driven forking and
skipping don't exist.

Proposed:

- `step.cond = fn(ctx)` — when false, the step is skipped (neither rendered
  nor counted done) on start and on resume.
- `def.steps` may be a function `(ctx) -> list`, re-evaluated on start and on
  resume so the tour shape can depend on the user's answers.
- (Deferred/optional) `step.next = "<id>"` to override linear advance; kept
  optional and out of the core so the default flow stays simple.

## File-level changes

| File | Change |
|---|---|
| `lua/tutorial/state.lua` | `read`/`write` carry `answers` and `vars`; add the four accessors; `reset` clears them. |
| `lua/tutorial/engine.lua` | Seed `session.ctx` from `answers`/`vars` before `setup`; fire `step.enter` once on first present; fire `step.complete` in `finish_step`; own the capture-once prompt for input steps (via `input.lua`); honor `step.cond` and `def.steps`-as-function when locating the first incomplete step. |
| `lua/tutorial/checks.lua` | Interpolate `{ctx:...}` in spec path/pattern/glob args before matching. |
| `lua/tutorial/ui/step.lua` + `ui/panel.lua` | Interpolate `{ctx:...}` in `title`/`body`/`hint`; show an `[a]nswer` affordance when the current step has `input`. |
| `lua/tutorial/input.lua` | NEW — the prompt surface (`vim.fn.input` default), `validate`/`transform`/`slug` helpers, re-answer routing. Keeps the engine small. |
| `lua/tutorial/init.lua` | Re-export any ergonomic helpers (`input`/`slug`) without breaking the public API. |

## Test plan (add to `tests/tutorial_spec.lua`)

- `state`: `answers`/`vars` round-trip; `reset` clears them; re-answer
  overwrites.
- `engine`: input step stores into `ctx`; `enter`/`complete` fire once each;
  `cond` skips a step; `def.steps`-as-function honored on start and resume;
  re-answer routes.
- `checks`: interpolated path/pattern resolves against `ctx`.
- `ui`: `{ctx:...}` renders in `title`/`body`/`hint`; input step shows the
  `[a]nswer` affordance; focus stays in the workspace.
- End-to-end: a tour where the user names a thing, the tour scaffolds a file
  named by it, and a predicate completes once that file appears.

## Docs to keep consistent

Per `AGENTS.md`, `doc/tutorial.txt` and `docs/authoring.md` must match the
schema. Both gain: `input` step field, `{ctx:...}` tokens, `enter`/`complete`
hooks, `cond`, and answer persistence. `docs/design.md` gains a short
rationale (calm input surface, never-trap skip, declarative step fields).
`docs/running.md` documents the new `[a]nswer` / `r` keys.

## Back-compat

All additions are optional step *fields* and an additive JSON shape. Existing
definitions are unaffected; `{key:X}` semantics are unchanged; `M.start`
reads answers only when present. No breaking public-API change.

## Scope / phasing

1. **Phase 1 — the unblocker**: input step + answer persistence +
   `{ctx:...}` tokens + `enter`/`complete` hooks + `slug` helper. This alone
   lets a tutorial ask for a name, scaffold by it, and speak it back.
2. **Phase 2 — adaptive**: interpolate tokens in spec args + `cond` +
   re-answer (`r`).
3. **Phase 3 — optional**: `def.steps`-as-function + `step.next` routing.

## Verification

Run the suite and the linters from inside the devshell (see `AGENTS.md`):
`nix flake check`, or the fast path
`nvim --headless -u NONE -l tests/tutorial_spec.lua` plus
`nix develop -c stylua --check lua/ plugin/ tests/`.
