# Roadmap: observation, pedagogy, and portable tutorials

> Status: **phases 0–4 implemented** (2026-08-23); phase 5 deliberately
> deferred. Grows the engine's ability to *observe* real editor activity,
> to *teach* in the moment rather than only track, and to travel as data.
> Written against the tree as of 2026-08-23.

## Decisions on record

| Question | Decision |
| --- | --- |
| Negative feedback (mistake detection) vs "calm" | Include — author-declared, gentle, never advancing |
| Authoring format for sharing | JSON (`.tutorial.json`), declarative-only; Lua stays canonical |
| Markdown / YAML / TOML formats | Rejected: ad-hoc conventions hide errors / no core parsers |
| VS Code walkthrough compatibility | Skipped entirely — `onCommand:` semantics diverge fundamentally; an importer would promise more than it can translate honestly |
| Distribution ambition | Files only (`load_file`, `:Tutorial load`); no network code in core |
| Agent-generated tutorials (Phase 5) | Deferred — design settled below, implementation postponed |

## Phase 0 — groundwork (done)

Public `tutorial.var()` writer so persisted vars are reachable outside tests;
config validation that warns on unknown options and bad values instead of
silently dropping them; public `validate(def)` linting extracted from the
registry; dead code removed (`checks.edge_kind`, `panel.bar`); done-screen
content deduplicated into one source; consistent footers;
`on_file_contains` tries successive path/pattern splits so paths containing
colons survive.

## Phase 1 — observation specs (done)

All through the single hub:

- `on_key:<lhs>` via one engine-owned `vim.on_key` listener; notation
  resolves against real mappings; literal-notation feeds match too
- `on_command:X!` demands a clean run (`v:errmsg` snapshot at CmdlineEnter)
- glob matching for `on_event:` patterns (`*`, `?`)
- state specs `on_buf_contains:<pat>` and `on_diagnostic:[severity]`
- opt-in timer polling (`poll_ms`) so `{context = fn}` truth tracks reality
  even while the user sits in insert mode

## Phase 2 — UI/UX polish (done)

`:Tutorial focus|next|prev|goto N|status`; highlight overrides applied after
defaults (authoritative, no `default` flag); explicit glyph tables plus an
`ascii` preset; distinct done/pending glyph faces; menu `/` filtering over
id/title/tags, inline tags, mouse row selection, staleness ("· 12d ago");
`status("percent")` and `status("step")` variants; unknown setup options warn.

## Phase 3 — pedagogy layer (done)

- Hint ladders: `hint` accepts a list; `h` climbs one rung per press,
  wrapping to hidden — fading support instead of front-loading it
- Recall masking: `recall = true` renders `{key:…}` tokens as `[hidden]`
  until revealed — retrieval before revelation
- Mistakes: author-declared `{ match, message }` pairs matched against typed
  command words and key sequences; they surface gentle copy and never advance
  (a mistake outranks a completion spec firing on the same action)
- Sections: `def.sections = { { title, steps } }` chunk headers for long tours
- Analytics: opt-in local time/hint/mistake telemetry + `:Tutorial stats`;
  menu shows how long ago a finished tour was completed

## Phase 4 — authoring & portability (done)

- Register-time linting through public `validate()`; warnings notify, errors
  refuse registration (messages unchanged)
- `:Tutorial new <id>` writes a commented scaffold that lints clean
- `.tutorial.json` portable format decoded with core `vim.json`, purity-checked
  (`assert_pure`) and structurally validated; input steps validate via
  `pattern`/`message` instead of function validators
- `load_file(path)` / `:Tutorial load <path>` dispatch `.lua` (full power)
  vs `.tutorial.json` (pure data)
- Progress files carry `"version": 1`; readers tolerate older shapes

## Phase 5 — agent co-authoring (deferred, design settled)

Strictly optional, off by default, zero in-core dependencies. When picked up:

1. **Machine-safe surface** — `validate()` + `assert_pure()` already exist;
   agents emit declarative-only content (no executable hooks), enforced by
   the purity guard rather than trust.
2. **Read-only signal** — promote the analytics event points into a small
   subscription API on the existing hub (`step_presented`, `step_completed`,
   `hint_shown{level}`, `mistake_detected`, `input_answered`). Nothing leaves
   the machine; consumers bring their own transport.
3. **Transport** — a watched inbox directory under
   `stdpath("data")/tutorial/inbox/` (files-first, matching the distribution
   stance) plus documented msgpack-RPC usage of the Lua API. No bundled HTTP
   servers, no in-core LLM clients beyond what users explicitly configure.
4. **OpenAI-compatible generation** — `setup({ agent = { enabled, provider =
   { base_url, api_key ($TUTORIAL_API_KEY → $OPENAI_API_KEY), model,
   timeout_ms } } })`; schema-constrained chat completions produce definitions
   that must clear validate + purity before registering; async curl with the
   key passed via a 0600 temp header file; injectable HTTP runner for tests.
5. **Guardrails** — registrations carry a source tag; sessions guided by
   external edits show a quiet marker; done-state immutable; changes land at
   next advance/resume; rate-limited re-registration.
6. **Pedagogical contract** (`docs/agents.md`, to write): calibrate
   difficulty to the learner, ladder hints before revealing, treat mistakes
   as teaching moments, pre-test before instructing, one idea per step, and
   the absolute rules — never remove manual `d`, never move focus, never
   extend a session uninvited.

Rationale for deferral: phases 1–4 stand alone, and the agent loop is only as
good as the observation signal and validation boundary beneath it — both now
exist and can settle before anything consumes them.

## Verification

Per AGENTS.md: whole gate is `nix flake check`; fast paths are
`nvim --headless -u NONE -l tests/tutorial_spec.lua` and
`nix develop -c stylua --check lua/ plugin/ tests/`. New modules must be
staged (`git add`) before Nix can see them in checks.
