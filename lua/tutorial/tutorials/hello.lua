-- tutorial.tutorials.hello
-- The built-in "Hello, tutorial.nvim" tour: a hands-on walk across every
-- completion mechanism the engine supports — and one input step, because the
-- engine can also ask. It is the engine's own proof of life — if this
-- tutorial can be finished, the engine works.

local M = {}

M.def = {
  id = "hello",
  title = "Hello, tutorial.nvim",
  summary = "A hands-on tour of the engine itself — every step uses a different mechanism.",
  steps = {
    {
      id = "manual",
      title = "Complete a step by hand",
      body = {
        "This is a step card. You are learning tutorial.nvim inside tutorial.nvim.",
        "",
        "Steps complete when their completion events fire — but {key:d} always",
        "works, so a tutorial can never trap you.",
        "",
        "Press {key:d} now to check this step off.",
      },
      hint = "d is for done. n and p flip through steps without completing them.",
      -- No completion specs: the manual path is the lesson.
    },
    {
      id = "command",
      title = "Complete a step with a command",
      body = {
        "The engine observes the Ex command line as you leave it.",
        "",
        "Run  :echo 'one small step'  and this step checks itself off.",
      },
      hint = "Any command line whose first word is `echo` completes this step.",
      completion = { "on_command:echo" },
    },
    {
      id = "file",
      title = "Complete a step by saving a file",
      body = {
        "State checks poll the filesystem, and saving fires them.",
        "",
        "Run  :edit tutorial-practice.md  then  :write  — the mere existence",
        "of that file completes this step.",
      },
      hint = "Delete the file afterwards; it is only practice scaffolding.",
      completion = { "on_file_exists:tutorial-practice.md" },
    },
    {
      id = "event",
      title = "Complete a step with an autocmd event",
      body = {
        "Plugins usually fire User events when something happens:",
        "",
        "Run  :doautocmd User TutorialPractice",
      },
      hint = "doautocmd fakes the event; a real plugin would fire it itself.",
      completion = { "on_event:TutorialPractice" },
    },
    {
      id = "predicate",
      title = "Complete a step with a predicate",
      body = {
        "The most flexible check is a plain Lua predicate polled by the engine.",
        "This step completes once your progress file exists — which it already",
        "does, because earlier steps earned their keep. Predicates receive the",
        "session ctx, so they can watch your answers too.",
      },
      hint = "Progress lives in stdpath('data')/tutorial/<id>.json.",
      completion = {
        {
          context = function()
            return require("tutorial.state").has_progress(M.def.id)
          end,
        },
      },
    },
    {
      id = "ask",
      title = "Answer a question",
      body = {
        "Steps can ask you things, too — this tour would like your name.",
        "",
        "Answer the prompt on the command line; focus never moves. The answer",
        "joins ctx (as ctx.name), later steps can speak it back, and it",
        "survives quitting. <Esc> skips the question; {key:d} still works —",
        "a tutorial can never trap you.",
      },
      hint = "The prompt fires once per session; press r to re-answer anytime.",
      input = {
        question = "Your name",
        store = "name",
      },
      -- Answering stores the answer, which alone satisfies this predicate.
      completion = {
        {
          context = function(ctx)
            return ctx.name ~= nil
          end,
        },
      },
    },
    {
      id = "wrapup",
      title = "You made it",
      body = {
        "That was every completion mechanism: manual, command, file state,",
        "events, predicates — and one question, answered by you.",
        "",
        "{ctx:greeting}",
        "",
        "Reset this tour from the menu ({key:r} on it) to replay, then write",
        "one for your own plugin — see :h tutorial-authoring.",
      },
      hint = "The menu also lives at :Tutorial. Your name rides along on resume.",
      enter = function(ctx)
        if ctx.name then
          ctx.greeting = ("Pleased to meet you, %s."):format(ctx.name)
        else
          ctx.greeting = "No name given — no worries; d carries every step."
        end
      end,
    },
  },
}

return M
