-- Run with: nvim --headless -u NONE -l tests/tutorial_spec.lua
local root = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
vim.opt.runtimepath:prepend(root)

local passed, failed = 0, 0
local function assert_true(condition, label)
  if condition then
    passed = passed + 1
    print("PASS " .. label)
  else
    failed = failed + 1
    print("FAIL " .. label)
  end
end

local tutorial = require("tutorial")
local registry = tutorial._registry
local engine = tutorial._engine
local state = tutorial._state
local checks = tutorial._checks

-- Isolated data dir per run.
state._set_dir(vim.fn.tempname() .. "/progress")

-- --- Registry ----------------------------------------------------------------

registry._clear()
local ok, err = pcall(registry.register, { title = "no id" })
assert_true(not ok and err:find("requires an id", 1, true), "definition without id rejected")

registry.register({
  id = "alpha",
  title = "Alpha",
  summary = "The first one",
  steps = {
    { id = "a1", title = "One", body = { "do one" } },
    { id = "a2", title = "Two", body = "do two", completion = { "on_command:Alpha" } },
  },
})
assert_true(registry.get("alpha") ~= nil, "register + get round-trips")
ok, err = pcall(registry.register, {
  id = "dup-step",
  title = "Dup",
  steps = { { id = "x", title = "X", body = "b" }, { id = "x", title = "Y", body = "b" } },
})
assert_true(not ok and err:find("duplicate step id", 1, true), "duplicate step id rejected")

-- Re-registering keeps menu position but swaps the definition.
registry.register({
  id = "alpha",
  title = "Alpha2",
  steps = { { id = "z", title = "Z", body = "b" } },
})
assert_true(
  #registry.list() == 1 and registry.list()[1].title == "Alpha2",
  "re-register replaces in place"
)

registry._clear()

-- --- State -------------------------------------------------------------------

state._set_dir(vim.fn.tempname() .. "/progress2")
local sdef = {
  id = "tut",
  title = "Tut",
  steps = {
    { id = "s1", title = "S1", body = "b" },
    { id = "s2", title = "S2", body = "b" },
    { id = "s3", title = "S3", body = "b" },
  },
}
assert_true(
  state.progress(sdef) == 0 and select(2, state.progress(sdef)) == "s1",
  "fresh progress is empty"
)
state.mark_done("tut", "s1")
assert_true(state.is_done("tut", "s1"), "mark_done registers")
state.mark_done("tut", "s1")
local count, next_id = state.progress(sdef)
assert_true(count == 1 and next_id == "s2", "progress counts done and finds next")
assert_true(state.reset("nope") == false, "reset of unknown tutorial reports false")
state.mark_done("tut", "s2")
assert_true(
  state.reset("tut") == true and not state.is_done("tut", "s1"),
  "reset clears a tutorial"
)

-- --- Checks ------------------------------------------------------------------

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
vim.fn.writefile({ "hello world", "storyteller: note here" }, tmp .. "/notes.md")
vim.fn.writefile({}, tmp .. "/marker.txt")

local parsed = checks.parse("on_file_exists:" .. tmp .. "/*.txt")
assert_true(checks.evaluate(parsed), "on_file_exists matches glob")
parsed = checks.parse("on_file_exists:" .. tmp .. "/missing-*")
assert_true(not checks.evaluate(parsed), "on_file_exists misses absent files")

parsed = checks.parse("on_file_contains:" .. tmp .. "/notes.md:storyteller:")
assert_true(checks.evaluate(parsed), "on_file_contains finds pattern")
parsed = checks.parse("on_file_contains:" .. tmp .. "/notes.md:nowhere$")
assert_true(not checks.evaluate(parsed), "on_file_contains misses absent pattern")
parsed = checks.parse("on_file_contains:" .. tmp .. "/gone.md:x")
assert_true(not checks.evaluate(parsed), "on_file_contains tolerates missing file")

parsed = checks.parse("on_command:Story idea")
assert_true(
  checks.evaluate(parsed, { command = "Story idea extra args" }),
  "on_command matches with args"
)
assert_true(checks.evaluate(parsed, { command = "Story idea" }), "on_command matches bare command")
assert_true(
  not checks.evaluate(parsed, { command = "Story ideas" }),
  "on_command respects word boundary"
)
assert_true(not checks.evaluate(parsed, {}), "on_command without payload is false")

parsed = checks.parse("on_event:MyPluginSaved")
assert_true(checks.evaluate(parsed, { event = "MyPluginSaved" }), "on_event matches pattern")
assert_true(not checks.evaluate(parsed, { event = "Other" }), "on_event rejects other patterns")

parsed = checks.parse("on_buffer:notes%.md$")
local nbuf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(nbuf, tmp .. "/notes.md")
assert_true(checks.evaluate(parsed, { buf = nbuf }), "on_buffer matches path suffix")
local obuf = vim.api.nvim_create_buf(false, true)
assert_true(not checks.evaluate(parsed, { buf = obuf }), "on_buffer rejects non-matching buffer")

parsed = checks.parse({
  context = function()
    return 1 > 0
  end,
})
assert_true(checks.evaluate(parsed), "context predicate truthy")
parsed = checks.parse({
  context = function()
    error("boom")
  end,
})
assert_true(not checks.evaluate(parsed), "erroring context predicate is safe-false")

ok, err = pcall(checks.parse, "on_nonsense:x")
assert_true(not ok and err:find("unknown completion spec", 1, true), "unknown spec kind rejected")

-- --- Engine ------------------------------------------------------------------

registry._clear()
state._set_dir(vim.fn.tempname() .. "/progress3")

local setup_calls, teardown_calls = 0, 0
local ctx_seen
local flag = false
registry.register({
  id = "demo",
  title = "Demo",
  layout = "card",
  setup = function(ctx)
    setup_calls = setup_calls + 1
    ctx.baseline = 7
  end,
  teardown = function(ctx)
    teardown_calls = teardown_calls + 1
    ctx_seen = ctx.baseline
  end,
  steps = {
    {
      id = "one",
      title = "First",
      body = { "Press {key:<leader>x} now.", "Then {key:keep going friend}." },
      hint = "It is obvious.",
      completion = {
        {
          context = function()
            return flag
          end,
        },
      },
    },
    {
      id = "two",
      title = "Second",
      body = "flag step",
      completion = {
        {
          context = function()
            return flag
          end,
        },
      },
    },
    { id = "three", title = "Third", body = "command step", completion = { "on_command:Demo go" } },
  },
})

local session = engine.start_id("demo")
assert_true(
  session ~= nil and setup_calls == 1 and session.ctx.baseline == 7,
  "start runs setup into ctx"
)
assert_true(vim.fn.exists("#tutorial_hub") == 1, "hub autocmds installed while active")

local card_buf = vim.api.nvim_win_get_buf(0)
local lines = table.concat(vim.api.nvim_buf_get_lines(card_buf, 0, -1, false), "\n")
assert_true(
  lines:find("DEMO", 1, true) ~= nil and lines:find("First", 1, true) ~= nil,
  "step card renders title"
)
assert_true(lines:find("<leader>x", 1, true) ~= nil, "key token rendered verbatim")
assert_true(lines:find("keep going friend", 1, true) ~= nil, "prose token rendered")

-- Manual completion advances to the next incomplete step.
engine.done()
assert_true(state.is_done("demo", "one") and not state.is_done("demo", "two"), "done marks sticky")
lines = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(0), 0, -1, false), "\n")
assert_true(lines:find("Second", 1, true) ~= nil, "card advanced to next incomplete step")

-- Edge trigger via explicit evaluation.
flag = true
engine._evaluate({})
assert_true(state.is_done("demo", "two"), "state predicate completes step")
lines = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(0), 0, -1, false), "\n")
assert_true(lines:find("Third", 1, true) ~= nil, "advanced after predicate completion")

-- Command observation completes the final step; done screen replaces card.
engine._dispatch_command("Demo go --fast")
assert_true(state.is_done("demo", "three"), "command spec completes step")
assert_true(engine.active() == nil, "session cleared on completion")
assert_true(vim.fn.exists("#tutorial_hub") == 0, "hub removed after completion")
assert_true(teardown_calls == 1 and ctx_seen == 7, "teardown ran with ctx")
lines = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(0), 0, -1, false), "\n")
assert_true(lines:find("TUTORIAL COMPLETE", 1, true) ~= nil, "done screen shown")

-- Resume skips completed steps; replay requires reset.
session = engine.start_id("demo")
assert_true(session == nil, "finished tutorial refuses to restart")
state.reset("demo")
session = engine.start_id("demo")
assert_true(session.index == 1, "reset allows replay from first step")

-- Navigation without completing.
engine.goto_step(1)
lines = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(0), 0, -1, false), "\n")
assert_true(lines:find("Second", 1, true) ~= nil, "goto_step moves forward")
engine.goto_step(-1)
lines = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(0), 0, -1, false), "\n")
assert_true(lines:find("First", 1, true) ~= nil, "goto_step moves backward")
engine.goto_step(-5)
assert_true(engine.active().index == 1, "goto_step clamps at bounds")

-- Quit persists progress and tears the hub down.
state.mark_done("demo", "one")
engine.quit()
assert_true(
  engine.active() == nil and vim.fn.exists("#tutorial_hub") == 0,
  "quit clears session + hub"
)
session = engine.start_id("demo")
assert_true(session.index == 2, "resume lands on first incomplete step")
engine.quit(true)

-- Unknown id refused.
assert_true(engine.start_id("ghost") == nil, "unknown tutorial id refused")

-- --- Menu UI -----------------------------------------------------------------

require("tutorial.ui.menu").open()
local menu_buf = vim.api.nvim_win_get_buf(0)
lines = table.concat(vim.api.nvim_buf_get_lines(menu_buf, 0, -1, false), "\n")
assert_true(
  lines:find("Demo", 1, true) ~= nil and lines:find("in progress", 1, true) ~= nil,
  "menu lists tutorials with progress"
)
vim.api.nvim_buf_delete(menu_buf, { force = true })

-- --- :Tutorial command -------------------------------------------------------

-- plugin/ scripts don't source under -u NONE before the spec runs; setup is
-- idempotent, so invoke it the way a real config would have.
tutorial.setup()
assert_true(vim.fn.exists(":Tutorial") == 2, ":Tutorial command defined")
assert_true(registry.get("demo") ~= nil, "registered id available as completion source")

-- --- Built-in hello tour (end-to-end proof) ----------------------------------

registry._clear()
state._set_dir(vim.fn.tempname() .. "/progress4")
local hello = require("tutorial.tutorials.hello").def
registry.register(hello)

-- Isolated working dir so the practice file never lands in a real project.
local original_cwd = vim.fn.getcwd()
local workdir = vim.fn.tempname()
vim.fn.mkdir(workdir, "p")
vim.cmd("cd " .. vim.fn.fnameescape(workdir))

session = engine.start_id("hello")
assert_true(session ~= nil and session.index == 1, "hello tour starts at manual step")

-- 1. manual path
engine.done()
assert_true(state.is_done("hello", "manual"), "hello: manual step completes by hand")

-- 2. command observation
engine._dispatch_command("echo 'one small step'")
assert_true(state.is_done("hello", "command"), "hello: echo completes command step")

-- 3. filesystem state, polled
engine._evaluate({})
assert_true(not state.is_done("hello", "file"), "hello: file step pending before save")
vim.fn.writefile({ "practice" }, workdir .. "/tutorial-practice.md")
engine._evaluate({})
assert_true(state.is_done("hello", "file"), "hello: saved file completes file step")

-- 4. real autocmd through the hub: doautocmd queues, vim.wait pumps schedules.
vim.cmd("doautocmd User TutorialPractice")
assert_true(
  vim.wait(200, function()
    return state.is_done("hello", "event")
  end),
  "hello: User event completes event step via scheduled hub"
)

-- 5. predicate over persisted progress
engine._evaluate({})
assert_true(state.is_done("hello", "predicate"), "hello: predicate sees progress file")

-- 6. wrap-up completes the tour
engine.done()
assert_true(engine.active() == nil, "hello tour finishes cleanly")

-- The finished tour refuses replay until reset.
assert_true(engine.start_id("hello") == nil, "hello tour refuses replay when complete")
state.reset("hello")
assert_true(engine.start_id("hello") ~= nil, "hello tour replays after reset")
engine.quit(true)

vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
vim.fn.delete(workdir, "rf")

-- --- Built-in authoring tour (end-to-end) ------------------------------------

registry._clear()
state._set_dir(vim.fn.tempname() .. "/progress5")
local authoring = require("tutorial.tutorials.authoring").def
registry.register(authoring)

local adir = vim.fn.tempname()
vim.fn.mkdir(adir, "p")
vim.cmd("cd " .. vim.fn.fnameescape(adir))

session = engine.start_id("authoring")
assert_true(session ~= nil and session.index == 1, "authoring tour starts")

engine.done()
assert_true(state.is_done("authoring", "anatomy"), "authoring: anatomy done by hand")

-- Follow the tour's own instructions: write the starter definition to disk.
vim.fn.writefile({
  "return {",
  "  id = \"my-first\",",
  "  title = \"My first tutorial\",",
  "  steps = {",
  "    { id = \"hello\", title = \"Say hi\", body = { \"You are inside your own tutorial.\" } },",
  "    { id = \"act\", title = \"Do a thing\", body = { \"Run :echo well hello there\" },",
  "      completion = { \"on_command:echo\" } },",
  "  },",
  "}",
}, adir .. "/my-tutorial.lua")
engine._evaluate({})
assert_true(state.is_done("authoring", "write"), "authoring: writing the file completes write")

-- Register it exactly like the tour tells users to.
registry.register(dofile(adir .. "/my-tutorial.lua"))
engine._evaluate({})
assert_true(state.is_done("authoring", "register"), "authoring: registry sees my-first")

engine.done()
assert_true(engine.active() == nil, "authoring tour finishes cleanly")

-- The payoff: the tutorial the user just wrote runs on the real engine.
session = engine.start_id("my-first")
assert_true(session ~= nil, "user-written tutorial starts")
lines = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(0), 0, -1, false), "\n")
assert_true(
  lines:find("MY FIRST TUTORIAL", 1, true) ~= nil and lines:find("Say hi", 1, true) ~= nil,
  "user-written card renders its own title"
)
engine.done()
engine._dispatch_command("echo well hello there")
assert_true(engine.active() == nil, "user-written tutorial completes end to end")

state.reset("authoring")
vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
vim.fn.delete(adir, "rf")

print(("RESULT: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
