# Design notes

Why the engine is the way it is. Short version: it descends from `vimtutor`,
borrows VS Code's walkthrough model, and refuses everything that made those
hard to reuse.

## Lineage

- **vimtutor** proved users learn by doing, inside the editor, with training
  wheels. It also proved a hand-written single document does not scale to a
  plugin ecosystem.
- **VS Code walkthroughs** contributed the shape worth copying: declarative
  steps with completion events, sticky check-offs, explicit reset.
- **VimTeacher and friends** showed the value of a central orchestrator and of
  data-driven lessons; adding content should never mean writing plumbing.

## Principles

1. **Declarative first.** If a step cannot be described as data — an event,
   a state predicate — it probably should not be a step. Programmatic step
   types can come later; they must not be the default path.
2. **Never trap the user.** Manual completion (`d`) is available on every
   step, always. Environments differ; a tutorial that hard-fails teaches the
   wrong lesson about the plugin behind it.
3. **Sticky progress.** Events check off; only people un-check, explicitly,
   via reset. Resume lands on the first incomplete step. A finished tutorial
   refuses replay until reset — replay is a decision, not an accident.
4. **One hub.** While a session is active, a single autocmd group observes
   the editor (User events, command lines, buffer entries, saves, cursor
   holds) and feeds only the current step's checks. Tutorials attach nothing;
   plugins ship definitions, not listeners.
5. **Calm.** One card at a time, no timers, no floating chrome. The tutorial
   is a colleague pointing at your screen, not a circus.
6. **Focus belongs to the user.** A running tutorial pins its panel and
   updates it silently; advancing never moves the cursor, swaps the workspace
   buffer, or steals the window. Deliberate actions (`s`, `:Tutorial`) are
   the only things that bring the panel forward.

## Asking the user anything

Interactive walkthroughs eventually need an answer, not just an observation
("name your protagonist", "pick a premise"). The same principles decide how:

- **The command line is the calm surface.** `vim.fn.input` draws at the
  bottom of the screen without touching window focus — the least intrusive
  place a question can live. Floating dialogs are chrome; the prompt is a
  colleague leaning over and asking.
- **Capture-once is engine-owned.** A prompt inside a polled predicate would
  refire on every BufEnter/CursorHold/render. The engine guards input steps
  per session instead; predicates stay pure observers.
- **Never trap, part two.** Cancelling a question is always allowed and just
  leaves the answer unset; `d` completes regardless. An unanswered step is a
  step with a nil answer, not a dead end.
- **Answers are data, not side effects.** They persist in the progress JSON,
  re-enter ctx before `setup` on resume, and flow back out through `{ctx:…}`/
  `{answer:…}` tokens in copy and completion args. Copy that cannot resolve a
  token shows the token itself — a visible typo beats silent emptiness.
- **Branching stays declarative.** `cond` on a step and steps-as-a-function
  shape the route from answers; there is no imperative "goto" in the core.
  The default remains a straight line.

## Mechanics worth knowing

- Every tutorial surface (pinned panel, card, menu, done screen) owns its
  window through a reuse registry: updates render into the registered window
  when it still exists and recreate it only when closed. This is what makes
  "pinned" possible and what keeps advances from stacking splits.
- Completion evaluation is **scheduled off-tick**: rendering a panel fires
  BufEnter, and completing a step mid-render would swap buffers under the
  renderer's feet. The hub defers, then guards against re-entrancy.
- Command observation happens on `CmdlineLeave`; matching is by leading
  command phrase, so `on_command:echo` survives arbitrary arguments but never
  matches `:echom`-style prefixes of longer names. A trailing `!`
  (`on_command:X!`) additionally demands proof of success — `v:errmsg`
  snapshotted at CmdlineEnter and compared on leave — because a step that
  checks off on a typo teaches the wrong lesson.
- State predicates are polled cheaply and often — card render, save, buffer
  entry, cursor hold, and an opt-in timer (`poll_ms`) — so "already true"
  conditions complete eagerly on display. That is a feature: write predicates
  that answer "is the world in the desired state", not "did the user just act".
- The session renders from a *resolved* step list: `def.steps` may be a
  function of ctx and `cond` drops steps the answers exclude. Skipped steps
  are not rendered, not counted, and never marked done — progress totals stay
  honest to what the user actually sees.

## Observation breadth

The engine watches more editor surfaces as steps demand them, but always
through the one hub: typed keys flow through a single engine-owned
`vim.on_key` listener (tutorials attach nothing), buffer text and diagnostics
are plain state predicates, and User-event matching accepts globs. Each
addition follows the same rule as the originals — declarative strings first,
functions only where nothing else can tell the truth.

## Teaching, not just tracking

Completion events say "well done"; three small features let tours also *teach*
in the moment:

- **Hint ladders** (`hint` as a list) fade support in on demand instead of
  front-loading every nudge — scaffolding that withdraws rather than smothers.
  The same key reveals **recall steps**, whose `{key:…}` tokens stay masked
  until the learner attempts the motion: retrieval before revelation.
- **Mistakes** are author-declared wrong actions with gentle corrective copy.
  They fire on exactly the actions the author anticipated, they never advance
  or trap (the note appears; the user remains in control), and they exist to
  turn a dead end into the lesson. A completion spec still outranks nothing:
  if the action would also have completed the step, the mistake wins — being
  corrected is worth more than an unearned checkmark.
- **Analytics** (`analytics = true`) record time-per-step, hint presses, and
  mistake hits locally, because authors cannot anticipate every error until
  they see where learners stall.

None of this changes the contract: `d` completes anything, focus never moves,
and a tutorial that cannot verify still cannot trap.

## Data that stays data

Definitions arriving from outside the codebase — shared `.tutorial.json`
files today — pass a purity check: no function values anywhere. That boundary
is what makes file-borne content safe by construction, and it is why JSON,
not Markdown/YAML/TOML, is the portable format: Neovim parses JSON in core
(zero dependencies), agents and humans emit it reliably, validation errors
have nowhere to hide, and Lua tables remain the full-power authoring surface
for everyone who wants predicates and hooks. Linting rides the same principle:
structural errors refuse registration, soft warnings surface loudly — a typo
in a shipped tour should be visible at load time, never discovered mid-tour.
