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
local panel = require("tutorial.ui.panel")

local function panel_lines()
  local buf = panel.buffer()
  assert_true(buf ~= nil and vim.api.nvim_buf_is_valid(buf), "panel buffer present")
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local function panel_windows()
  local out = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
      if name:find("tutorial://panel", 1, true) == 1 then
        out[#out + 1] = win
      end
    end
  end
  return out
end

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

-- 6. input step: the tour asks, the answer alone completes the step
require("tutorial.input")._driver = function()
  return "Cyrus"
end
assert_true(
  vim.wait(200, function()
    return state.answer("hello", "ask") == "Cyrus" and state.is_done("hello", "ask")
  end),
  "hello: answering the question stores and self-completes"
)

-- 7. wrap-up speaks the answer back via enter hook + {ctx:} token
lines = panel_lines()
assert_true(
  lines:find("Pleased to meet you, Cyrus", 1, true) ~= nil,
  "hello: wrapup greets the user by name"
)
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
  "    { id = \"who\", title = \"Say hi to {ctx:coder}\",",
  "      body = { \"Welcome aboard, {answer:who}.\" },",
  "      input = { question = \"Coder name\", store = \"coder\" },",
  "      completion = { { context = function(ctx) return ctx.coder ~= nil end } } },",
  "    { id = \"bye\", title = \"That is it\",",
  "      body = { \"You wrote, registered, and ran a real tutorial.\" } },",
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

-- The payoff: the tutorial the user just wrote runs on the real engine —
-- pinned in the panel, since it declares no layout.
session = engine.start_id("my-first")
assert_true(session ~= nil, "user-written tutorial starts")
lines = panel_lines()
assert_true(
  lines:find("MY FIRST TUTORIAL", 1, true) ~= nil and lines:find("Say hi", 1, true) ~= nil,
  "user-written card renders its own title"
)
require("tutorial.input")._driver = function()
  return "Ada"
end
engine.done()
engine._dispatch_command("echo well hello there")
assert_true(
  vim.wait(200, function()
    return state.answer("my-first", "who") == "Ada" and state.is_done("my-first", "who")
  end),
  "user-written input step asks, stores, and self-completes"
)
engine.goto_step(-1) -- view the question step again: it speaks the answer back
lines = panel_lines()
assert_true(
  lines:find("Welcome aboard, Ada", 1, true) ~= nil,
  "user-written card echoes the answer"
)
engine.goto_step(1)
engine.done()
assert_true(engine.active() == nil, "user-written tutorial completes end to end")

state.reset("authoring")
vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
vim.fn.delete(adir, "rf")

-- --- Menu selection regression -----------------------------------------------

-- Rows are selected by cursor line number; headers and summaries must not
-- desync them from the tutorial order.
registry._clear()
state._set_dir(vim.fn.tempname() .. "/progress6")
registry.register({
  id = "one",
  title = "One",
  summary = "has a summary line",
  steps = { { id = "s", title = "S", body = "b" } },
})
registry.register({
  id = "two",
  title = "Two",
  steps = { { id = "s", title = "S", body = "b" } },
})

local function open_menu()
  require("tutorial.ui.menu").open()
  local buf = vim.api.nvim_win_get_buf(0)
  return buf, vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function row_of(menu_lines, pat)
  for i, ln in ipairs(menu_lines) do
    if ln:find(pat, 1, true) then
      return i
    end
  end
end

local function press_cr()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "mx", false)
end

local _, lines_menu = open_menu()
vim.api.nvim_win_set_cursor(0, { row_of(lines_menu, "Two"), 0 })
press_cr()
assert_true(
  engine.active() ~= nil and engine.active().def.id == "two",
  "menu <CR> starts the tutorial under the cursor"
)
engine.quit(true)

_, lines_menu = open_menu()
vim.api.nvim_win_set_cursor(0, { row_of(lines_menu, "has a summary"), 0 })
press_cr()
assert_true(
  engine.active() ~= nil and engine.active().def.id == "one",
  "menu <CR> works on summary lines"
)
engine.quit(true)

open_menu()
press_cr()
assert_true(
  engine.active() ~= nil and engine.active().def.id == "one",
  "menu opens with cursor ready on the first entry"
)
engine.quit(true)

-- -- --- Pinned panel ------------------------------------------------------------

registry._clear()
state._set_dir(vim.fn.tempname() .. "/progress7")
-- Section hygiene: earlier tours leave their panels pinned; collapse to a
-- single clean window.
vim.cmd("silent! only!")
local pin_flag = false
registry.register({
  id = "pinned",
  title = "Pinned",
  -- no layout field: defaults to the pinned panel
  steps = {
    {
      id = "p1",
      title = "First",
      body = { "flag step" },
      completion = {
        {
          context = function()
            return pin_flag
          end,
        },
      },
    },
    { id = "p2", title = "Second", body = { "manual" } },
    {
      id = "p3",
      title = "Third",
      body = { "anchored file" },
      completion = { "on_file_exists:rel-marker.txt" },
    },
  },
})

-- Work in an isolated cwd for the anchoring checks below.
local pdir = vim.fn.tempname()
vim.fn.mkdir(pdir .. "/work", "p")
vim.cmd("cd " .. vim.fn.fnameescape(pdir))

local ws_win = vim.api.nvim_get_current_win()
local ws_buf = vim.api.nvim_win_get_buf(ws_win)
local ws_row = vim.api.nvim_win_get_cursor(ws_win)[1]

session = engine.start_id("pinned")
assert_true(panel.visible(), "panel visible after start")
assert_true(vim.api.nvim_get_current_win() == ws_win, "start does not steal focus")
assert_true(vim.api.nvim_win_get_buf(ws_win) == ws_buf, "workspace buffer untouched")

lines = panel_lines()
assert_true(
  lines:find("PINNED", 1, true) ~= nil and lines:find("First", 1, true) ~= nil,
  "panel renders current step"
)

-- Advancing updates the same window in place; focus and cursor stay put.
assert_true(#panel_windows() == 1, "exactly one panel window")
pin_flag = true
engine._evaluate({})
assert_true(state.is_done("pinned", "p1"), "pinned: predicate completes first step")
assert_true(#panel_windows() == 1, "advance creates no extra windows")
assert_true(vim.api.nvim_get_current_win() == ws_win, "advance keeps focus in workspace")
assert_true(vim.api.nvim_win_get_cursor(ws_win)[1] == ws_row, "workspace cursor untouched")

-- Hiding via :Tutorial toggle, then back.
vim.cmd("Tutorial")
assert_true(not panel.visible(), ":Tutorial hides a visible panel")
assert_true(vim.api.nvim_get_current_win() == ws_win, "hiding keeps focus in workspace")
vim.cmd("Tutorial")
assert_true(panel.visible(), ":Tutorial brings the panel back")

-- Closing the window by hand: the next advance recreates it.
local old_panel_win = panel_windows()[1]
vim.api.nvim_win_close(old_panel_win, true)
assert_true(not panel.visible(), "hand-closed panel is gone")
engine.goto_step(1)
assert_true(panel.visible() and #panel_windows() == 1, "panel recreated on next update")
assert_true(panel_windows()[1] ~= old_panel_win, "recreated panel is a fresh window")

-- Relative file specs anchor to the session's start cwd, not live cwd.
state.mark_done("pinned", "p2")
engine.goto_step(1)
assert_true(session.index == 3, "navigated to third step")
vim.fn.mkdir(pdir .. "/elsewhere", "p")
vim.cmd("cd " .. vim.fn.fnameescape(pdir .. "/elsewhere"))
engine._evaluate({})
assert_true(not state.is_done("pinned", "p3"), "anchored spec ignores unrelated cwd")
vim.fn.writefile({ "x" }, pdir .. "/rel-marker.txt")
engine._evaluate({})
assert_true(state.is_done("pinned", "p3"), "relative spec resolves against session cwd")

-- Finish: summary lives in the panel, focus stays, q dismisses and closes.
assert_true(engine.active() == nil, "pinned tutorial finished cleanly")
assert_true(panel.visible(), "done summary stays visible in panel")
assert_true(vim.api.nvim_get_current_win() == ws_win, "finish keeps workspace focused")
lines = panel_lines()
assert_true(lines:find("TUTORIAL COMPLETE", 1, true) ~= nil, "panel shows completion summary")

local panel_win = panel_windows()[1]
vim.api.nvim_set_current_win(panel_win)
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("q", true, false, true), "mx", false)
assert_true(not panel.visible(), "q dismisses the finished panel")
assert_true(vim.api.nvim_get_current_win() == ws_win, "dismissal returns focus to the workspace")

-- status() while idle vs running.
assert_true(tutorial.status() == nil, "status is nil when idle")
state.reset("pinned")
session = engine.start_id("pinned")
assert_true(
  tutorial.status() == "Pinned 0/3",
  ("status reports title and progress (got %q)"):format(tostring(tutorial.status()))
)
engine.done()
assert_true(tutorial.status() == "Pinned 1/3", "status tracks completed steps")

-- Quitting only owns its own surfaces: a menu open elsewhere survives.
require("tutorial.ui.menu").open()
local menu_buffer = vim.api.nvim_win_get_buf(0)
assert_true(
  vim.api.nvim_buf_get_name(menu_buffer):find("tutorial://menu", 1, true) == 1,
  "menu opened"
)
-- start replaces session; menu window stays where it is.
engine.quit(true)
assert_true(vim.api.nvim_buf_is_valid(menu_buffer), "quit does not wipe an open menu")

-- Card mode reuses one window: no accumulation across advances.
vim.cmd("silent! only!")
local function card_windows()
  local out = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
      if name:find("tutorial://step", 1, true) == 1 then
        out[#out + 1] = win
      end
    end
  end
  return out
end
registry.register({
  id = "carded",
  title = "Carded",
  layout = "card",
  steps = {
    { id = "c1", title = "C1", body = { "b" } },
    { id = "c2", title = "C2", body = { "b" } },
  },
})
engine.start_id("carded")
assert_true(#card_windows() == 1, "card renders once at start")
local windows_at_start = #vim.api.nvim_list_wins()
engine.done()
assert_true(#card_windows() == 1, "advance reuses the card window")
assert_true(
  #vim.api.nvim_list_wins() == windows_at_start,
  "advancing creates no new windows in card mode"
)
engine.quit(true)

-- --- Interactive & adaptive walkthroughs (input steps) ------------------------

registry._clear()
vim.cmd("silent! only!")
state._set_dir(vim.fn.tempname() .. "/progress8")
local input = tutorial._input

-- Stub the capture driver: prompts answer instantly, headless-safe.
local driver_calls
local driver_value -- value or function(spec)
input._driver = function(spec)
  driver_calls = driver_calls + 1
  if type(driver_value) == "function" then
    return driver_value(spec)
  end
  return driver_value
end

local function card_text()
  return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(0), 0, -1, false), "\n")
end

-- Input helpers: slug + token interpolation.
assert_true(input.slug("Ada Lovelace!") == "ada-lovelace", "slug lowercases and dashes")
assert_true(input.slug("  Weird__Name!!  ") == "weird-name", "slug trims and dedupes dashes")
assert_true(
  input.interpolate("Hi {ctx:name}", { name = "Cyrus" }, {}) == "Hi Cyrus",
  "{ctx:} token interpolates"
)
assert_true(
  input.interpolate("{answer:s1}", {}, { s1 = "Nova" }) == "Nova",
  "{answer:} token interpolates"
)
assert_true(
  input.interpolate("Hi {ctx:nope}", {}, {}) == "Hi {ctx:nope}",
  "unknown ctx token stays verbatim"
)
assert_true(
  input.interpolate("Press {key:<leader>x} now", {}, {}) == "Press {key:<leader>x} now",
  "key tokens pass through interpolation untouched"
)

-- Capture loop: transform then validate; invalid re-prompts; cancel bails.
driver_calls = 0
local queue = { "", "   ", "Ada" }
driver_value = function()
  return table.remove(queue, 1)
end
local spec = {
  question = "Q",
  transform = function(v)
    return (v:gsub("%s+", ""))
  end,
  validate = function(v)
    return v ~= ""
  end,
}
assert_true(input.capture(spec) == "Ada" and driver_calls == 3, "invalid answers re-prompt")
driver_value = function()
  return nil
end
assert_true(input.capture({ question = "Q" }) == nil, "cancel leaves capture unset")

-- State: answers/vars are re-writable and reset clears them.
state.set_answer("answers", "s1", "Cyrus")
assert_true(state.answer("answers", "s1") == "Cyrus", "answer round-trips")
state.set_answer("answers", "s1", "Nova")
assert_true(state.answer("answers", "s1") == "Nova", "re-answer overwrites stored value")
state.set_var("answers", "theme", "loss")
assert_true(state.get_var("answers", "theme") == "loss", "var round-trips")
state.reset("answers")
assert_true(
  state.answer("answers", "s1") == nil and state.get_var("answers", "theme") == nil,
  "reset clears answers and vars"
)

-- Checks: tokens resolve against trigger ctx/answers at evaluate time.
local cdir = vim.fn.tempname()
vim.fn.mkdir(cdir, "p")
parsed = checks.parse("on_file_exists:" .. cdir .. "/{ctx:who}.md")
assert_true(not checks.evaluate(parsed, { ctx = { who = "cyrus" } }), "interp glob misses first")
vim.fn.writefile({}, cdir .. "/cyrus.md")
assert_true(checks.evaluate(parsed, { ctx = { who = "cyrus" } }), "interp glob resolves")
vim.fn.writefile({ "the theme is loss" }, cdir .. "/notes-s1.md")
parsed = checks.parse("on_file_contains:" .. cdir .. "/notes-{answer:n}.md:{ctx:word}")
assert_true(
  checks.evaluate(parsed, { answers = { n = "s1" }, ctx = { word = "loss" } }),
  "interp path+pattern resolve"
)
assert_true(
  not checks.evaluate(parsed, { answers = { n = "s1" }, ctx = { word = "gain" } }),
  "interp pattern can miss"
)
parsed = checks.parse({
  context = function(c)
    return c.flag
  end,
})
assert_true(checks.evaluate(parsed, { ctx = { flag = true } }), "context predicate receives ctx")
assert_true(not checks.evaluate(parsed, {}), "context predicate without ctx is safe-false")

-- Registry accepts the new shapes.
ok, err = pcall(registry.register, {
  id = "bad-input",
  title = "t",
  steps = { { id = "s", title = "t", body = "b", input = "nope" } },
})
assert_true(not ok and err:find("input must be a table", 1, true), "non-table input rejected")
registry.register({
  id = "fn-steps",
  title = "FnSteps",
  steps = function()
    return { { id = "only", title = "Only", body = "b" } }
  end,
})
assert_true(registry.get("fn-steps") ~= nil, "function steps accepted")

-- Engine: an input step asks once per session, stores into ctx + progress.
local entered, completed = {}, {}
registry._clear()
registry.register({
  id = "asker",
  title = "Asker",
  layout = "card",
  steps = {
    {
      id = "name",
      title = "Name your lead",
      body = { "Your lead is {ctx:lead}." },
      hint = "Any name works.",
      enter = function()
        entered[#entered + 1] = "name"
      end,
      complete = function()
        completed[#completed + 1] = "name"
      end,
      input = {
        question = "Protagonist name",
        store = "lead",
        transform = function(v)
          return (v:gsub("^%s+", ""):gsub("%s+$", ""))
        end,
        validate = function(v)
          return v ~= "" or "needs a name"
        end,
      },
    },
    {
      id = "echo",
      title = "Welcome, {ctx:lead}",
      body = { "You chose {answer:name}." },
      hint = "Hint for {ctx:lead}",
      enter = function()
        entered[#entered + 1] = "echo"
      end,
      complete = function()
        completed[#completed + 1] = "echo"
      end,
    },
    {
      id = "mood",
      title = "Mood",
      body = { "Mood: {ctx:mood}" },
      enter = function()
        entered[#entered + 1] = "mood"
      end,
      complete = function()
        completed[#completed + 1] = "mood"
      end,
      input = { question = "Mood", store = "mood" },
    },
  },
})

driver_calls = 0
driver_value = "Cyrus"
session = engine.start_id("asker")
assert_true(session ~= nil, "asker tour starts")
lines = card_text()
assert_true(lines:find("[a]nswer", 1, true) ~= nil, "input step shows [a]nswer affordance")
assert_true(lines:find("{ctx:lead}", 1, true) ~= nil, "unanswered token renders verbatim")
assert_true(
  vim.wait(200, function()
    return state.answer("asker", "name") ~= nil
  end),
  "scheduled auto-prompt captured the answer"
)
assert_true(driver_calls == 1, "capture-once: exactly one prompt")
assert_true(session.ctx.lead == "Cyrus", "answer seeded into ctx under its store")
assert_true(#entered == 1 and entered[1] == "name", "enter fired once on first present")

-- Re-answer via r overwrites; navigation never re-fires enter.
driver_value = "  Nova  "
engine.answer()
assert_true(
  session.ctx.lead == "Nova" and state.answer("asker", "name") == "Nova",
  "re-answer overwrites (transform applied)"
)
assert_true(driver_calls == 2 and #entered == 1, "manual re-answer routes through one prompt")

engine.done()
assert_true(state.is_done("asker", "name"), "done completes the answered step")
assert_true(completed[1] == "name" and #completed == 1, "complete hook fired once")

lines = card_text()
assert_true(lines:find("Welcome, Nova", 1, true) ~= nil, "title echoes the current answer")
assert_true(lines:find("You chose Nova", 1, true) ~= nil, "body interpolates {answer:}")

-- Force a fresh render by toggling the hint (also proves hint interpolation),
-- revisiting the answered step; enters must not re-fire.
require("tutorial.ui.step").toggle_hint()
engine.goto_step(-1) -- view name again...
engine.goto_step(1) -- ...and back to echo
lines = card_text()
assert_true(lines:find("You chose Nova", 1, true) ~= nil, "render reflects re-answer")
assert_true(lines:find("Hint for Nova", 1, true) ~= nil, "hint interpolates ctx tokens")
assert_true(#entered == 2, "enter fires once per step per session")

-- Cancel path: mood prompts, user cancels, answer stays unset; d still works.
driver_value = function()
  return nil
end
engine.done() -- echo completes manually -> mood presents -> auto-prompt fires
assert_true(
  vim.wait(200, function()
    return driver_calls > 0
  end),
  "mood prompted automatically"
)
local calls_after_cancel = driver_calls
assert_true(state.answer("asker", "mood") == nil, "cancelled answer stays unset")
assert_true(not state.is_done("asker", "mood"), "cancel does not complete the step")
engine.done() -- never trap: manual completion works unanswered
assert_true(engine.active() == nil, "skipped input step finishes the tour")
assert_true(state.answer("asker", "mood") == nil, "d-skip leaves the answer nil")
assert_true(#entered == 3 and #completed == 3, "every step entered and completed exactly once")
assert_true(driver_calls == calls_after_cancel, "no stray re-prompt after cancel")

-- cond: skipped steps are neither rendered nor counted.
registry._clear()
state._set_dir(vim.fn.tempname() .. "/progress9")
registry.register({
  id = "branchy",
  title = "Branchy",
  steps = {
    { id = "a", title = "A", body = "a" },
    {
      id = "b",
      title = "B",
      body = "b",
      cond = function()
        return false
      end,
    },
    { id = "c", title = "C", body = "c" },
  },
})
session = engine.start_id("branchy")
assert_true(session ~= nil and #session.steps == 2, "cond-skipped step leaves the list")
assert_true(tutorial.status() == "Branchy 0/2", "status counts only live steps")
lines = panel_lines()
assert_true(lines:find("✧✧", 1, true) ~= nil, "bar shows two glyphs")
engine.done()
assert_true(
  session.steps[session.index].id == "c" and not state.is_done("branchy", "b"),
  "advance skips the excluded step"
)
engine.done()
assert_true(engine.active() == nil, "tour finishes without the excluded step")
state.reset("branchy")

-- def.steps as a function: shape follows persisted vars on start AND resume.
state._set_dir(vim.fn.tempname() .. "/progress10")
registry.register({
  id = "adaptive",
  title = "Adaptive",
  steps = function(ctx)
    if ctx.mode == "b" then
      return { { id = "sb", title = "SB", body = "b branch" } }
    end
    return { { id = "sa", title = "SA", body = "a branch" } }
  end,
})
session = engine.start_id("adaptive")
assert_true(session ~= nil and session.steps[1].id == "sa", "steps-function resolved on start")
engine.quit(true)
state.set_var("adaptive", "mode", "b")
session = engine.start_id("adaptive")
assert_true(
  session ~= nil and session.steps[1].id == "sb",
  "resume re-evaluates the steps-function from persisted vars"
)
engine.quit(true)

-- End-to-end: ask, scaffold a file named by the slugified answer, verify.
registry._clear()
state._set_dir(vim.fn.tempname() .. "/progress11")
local e2e_dir = vim.fn.tempname()
vim.fn.mkdir(e2e_dir, "p")
vim.cmd("cd " .. vim.fn.fnameescape(e2e_dir))
registry.register({
  id = "scaffold",
  title = "Scaffold",
  layout = "card",
  steps = {
    {
      id = "name-it",
      title = "Name it",
      body = { "We will create story-{ctx:lead}.md." },
      input = {
        question = "Lead name",
        store = "lead",
        transform = input.slug,
        validate = function(v)
          return v ~= ""
        end,
      },
      completion = { "on_file_exists:story-{ctx:lead}.md" },
    },
    { id = "wrap", title = "Wrap {ctx:lead}", body = { "Done with {answer:name-it}." } },
  },
})
driver_calls = 0
driver_value = "Ada Lovelace!"
session = engine.start_id("scaffold")
assert_true(
  vim.wait(200, function()
    return session.ctx.lead == "ada-lovelace"
  end),
  "slug transform applied to captured answer"
)
lines = card_text()
assert_true(
  lines:find("story%-ada%-lovelace%.md", 1, false) ~= nil,
  "copy speaks the user's own name"
)
assert_true(not state.is_done("scaffold", "name-it"), "not done before the file exists")
vim.fn.writefile({}, e2e_dir .. "/story-ada-lovelace.md")
engine._evaluate({})
assert_true(state.is_done("scaffold", "name-it"), "interpolated glob verifies the scaffold")
lines = card_text()
assert_true(lines:find("Wrap ada%-lovelace", 1, false) ~= nil, "next step adapts to the answer")
engine.done()
assert_true(engine.active() == nil, "scaffold tour completes end to end")

input._driver = function()
  error("unexpected prompt after input tests")
end
vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
vim.fn.delete(e2e_dir, "rf")

print(("RESULT: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
