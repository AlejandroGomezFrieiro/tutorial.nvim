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

## Mechanics worth knowing

- Completion evaluation is **scheduled off-tick**: rendering a card fires
  BufEnter, and completing a step mid-render would swap buffers under the
  renderer's feet. The hub defers, then guards against re-entrancy.
- Command observation happens on `CmdlineLeave`; matching is by leading
  command word, so `on_command:echo` survives arbitrary arguments but never
  matches `:echom`-style prefixes of longer names.
- State predicates are polled cheaply and often — card render, save, buffer
  entry, cursor hold — so "already true" conditions complete eagerly on
  display. That is a feature: write predicates that answer "is the world in
  the desired state", not "did the user just act".
