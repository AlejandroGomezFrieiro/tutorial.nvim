-- demo-tour.lua
-- The recording companion for demo.tape: a three-step tour that parades the
-- newer engine features — hint ladders, recall masking, and mistake
-- corrections — in under half a minute. Loaded live in the recording via
-- :Tutorial load, so the loader gets screen time too.

return {
  id = "showcase",
  title = "What's new",
  summary = "Hint ladders, hidden keys, and gentle corrections",
  tags = { "whats-new", "pedagogy" },
  steps = {
    {
      id = "ladder",
      title = "Hints arrive one rung at a time",
      body = {
        "Press {key:h} once for a nudge, again for more.",
        "",
        "Then press {key:d} to move on.",
      },
      hint = {
        "Rung one: h climbs the ladder.",
        "Rung two: another press wraps back to hidden.",
      },
    },
    {
      id = "recall",
      title = "Try before you peek",
      body = {
        "This step hides its answer: run {key::DemoReveal}.",
        "",
        "Stuck? {key:h} uncovers what the card is really asking.",
      },
      recall = true,
      hint = "Recall steps mask {key:…} tokens until you ask for help.",
      completion = { "on_command:DemoReveal" },
    },
    {
      id = "mistakes",
      title = "Wrong moves become lessons",
      body = {
        "Announce it: run :demosay done.",
        "",
        "Typing the capitalised cousin teaches you why not to.",
      },
      mistake = {
        { match = "Echo", message = "Lowercase wins here — try :demosay instead." },
      },
      completion = { "on_command:demosay" },
    },
  },
}
