-- tutorial.engine
-- Runs one active tutorial session and owns the single autocmd hub that feeds
-- the current step's completion checks. Tutorials never attach their own
-- autocmds; everything flows through here.
--
-- Hub events and what they feed:
--   User *       → on_event edge specs
--   CmdlineLeave → on_command edge specs (via getcmdline())
--   BufEnter     → on_buffer edge specs + state poll
--   BufWritePost → state poll
--   CursorHold   → state poll
--
-- Presentation: layout "card" renders full-window cards (reused window);
-- anything else — the default — pins the walkthrough panel beside the
-- workspace and never moves the user's focus.
--
-- The session carries its own resolved view of the tour (`session.steps`):
-- def.steps may be a function of ctx, and steps whose `cond` excludes them
-- are neither rendered nor counted. Input steps prompt through input.lua
-- under an engine-owned capture-once guard; answers land in ctx and the
-- progress file, so copy, checks, and resume all see them.

local registry = require("tutorial.registry")
local state = require("tutorial.state")
local checks = require("tutorial.checks")

local M = {}

local session -- { def, steps, index, ctx, answers, cwd, prev_win, entered,
-- asked } or nil
local advancing -- guards against re-entrant evaluation while a completion is
-- being processed (rendering the next card fires BufEnter, which would
-- otherwise evaluate again and delete the buffer mid-render)
-- Mutually recursive trio: present schedules input capture, capture nudges
-- evaluation, evaluation advances and presents again.
local present, ask_current, evaluate

local function step()
  if not session then
    return nil
  end
  return session.steps[session.index]
end

local function notify(msg, level)
  vim.notify("[tutorial] " .. msg, level or vim.log.levels.INFO)
end

local function panel_mode()
  return session ~= nil and session.def.layout ~= "card"
end

-- Seed persisted answer values into ctx under their input stores. Idempotent;
-- run against both static and resolved step lists (a steps-function's stores
-- are unknowable until it runs).
local function seed_answers(ctx, steps, answers)
  for _, s in ipairs(steps) do
    if type(s) == "table" and s.input then
      local stored = answers[s.id]
      if stored ~= nil then
        ctx[s.input.store or s.id] = stored
      end
    end
  end
end

-- The context a definition sees outside any active session: persisted vars
-- plus answer-store seeds. Second return is the raw answers map.
function M.context_for(def)
  local data = state.load(def.id)
  local ctx = {}
  for key, value in pairs(data.vars or {}) do
    ctx[key] = value
  end
  if type(def.steps) == "table" then
    seed_answers(ctx, def.steps, data.answers or {})
  end
  return ctx, data.answers or {}
end

-- Resolve a definition's effective step list for a context: def.steps may be
-- a function(ctx) -> list, and steps whose cond excludes them drop out
-- (neither rendered nor counted). Errors in either hook degrade to a
-- notification, never a crash — never trap the user.
function M.resolve_steps(def, ctx)
  local raw = def.steps
  if type(raw) == "function" then
    local ok, list = pcall(raw, ctx)
    if ok and type(list) == "table" then
      raw = list
    else
      notify(("steps() failed for %q: %s"):format(def.title, tostring(list)), vim.log.levels.ERROR)
      raw = {}
    end
  end
  local out = {}
  for _, s in ipairs(raw) do
    if type(s) == "table" then
      local keep = true
      if type(s.cond) == "function" then
        local ok, res = pcall(s.cond, ctx)
        keep = ok and res ~= nil and res ~= false
      end
      if keep then
        out[#out + 1] = s
      end
    end
  end
  return out
end

-- Route the current step to its surface: pinned panel or full-window card.
function present()
  if not session then
    return
  end
  local current = step()
  if not current then
    return
  end
  if type(current.enter) == "function" and not session.entered[current.id] then
    session.entered[current.id] = true
    local ok, err = pcall(current.enter, session.ctx)
    if not ok then
      notify(("step enter failed: %s"):format(err), vim.log.levels.ERROR)
    end
  end
  if panel_mode() then
    require("tutorial.ui.panel").update(session)
  else
    require("tutorial.ui.step").open(session)
  end
  -- Capture-once for input steps: the engine owns the guard (never a polled
  -- predicate), and the prompt fires off the render tick.
  if current.input and not session.asked[current.id] then
    vim.schedule(function()
      if session and session.steps[session.index] == current and not session.asked[current.id] then
        ask_current()
      end
    end)
  end
end

-- Prompt for the current input step and store the answer into the progress
-- file and ctx. Cancel leaves the answer unset; `d` always still completes.
-- Also the manual re-answer route ([a]nswer / r overwrite the stored value).
function ask_current()
  if not session or advancing then
    return
  end
  local current = step()
  if not current or not current.input then
    return
  end
  session.asked[current.id] = true
  local value = require("tutorial.input").capture(current.input)
  if value == nil then
    return
  end
  state.set_answer(session.def.id, current.id, value)
  session.answers[current.id] = value
  session.ctx[current.input.store or current.id] = value
  present() -- copy can now speak the user's own words back
  -- The answer alone may satisfy a polled predicate; nudge off the tick.
  vim.schedule(function()
    evaluate({})
  end)
end

M.answer = ask_current

local function finish_step(step_id)
  local finished
  for _, s in ipairs(session.steps) do
    if s.id == step_id then
      finished = s
      break
    end
  end
  state.mark_done(session.def.id, step_id)
  if finished and type(finished.complete) == "function" then
    local ok, err = pcall(finished.complete, session.ctx)
    if not ok then
      notify(("step complete failed: %s"):format(err), vim.log.levels.ERROR)
    end
  end
  local done_count = select(1, state.progress(session.def, session.steps))
  notify(("✓ %s (%d/%d)"):format((finished or step()).title, done_count, #session.steps))
  if done_count >= #session.steps then
    local def = session.def
    local prev_win = session.prev_win
    if def.teardown then
      pcall(def.teardown, session.ctx)
    end
    session = nil
    vim.api.nvim_del_augroup_by_name("tutorial_hub")
    if def.layout == "card" then
      require("tutorial.ui.done").open(def)
    else
      require("tutorial.ui.panel").finish(def)
      -- The panel never steals focus; keep it that way at finish too.
      if prev_win and vim.api.nvim_win_is_valid(prev_win) then
        pcall(vim.api.nvim_set_current_win, prev_win)
      end
    end
    return
  end
  -- Advance to the next incomplete step.
  for i, s in ipairs(session.steps) do
    if not state.is_done(session.def.id, s.id) then
      session.index = i
      break
    end
  end
  present()
end

local function run_completion(step_id)
  advancing = true
  local ok, err = pcall(finish_step, step_id)
  advancing = false
  if not ok then
    notify(("step completion failed: %s"):format(err), vim.log.levels.ERROR)
  end
end

-- Evaluate every check for the active step. Edge triggers pass a payload;
-- state predicates are always polled. Relative file specs resolve against the
-- working directory captured when the session started; {ctx:…}/{answer:…}
-- tokens resolve against the live session context and answers.
function evaluate(trigger)
  if not session or advancing then
    return false
  end
  trigger = trigger or {}
  trigger.cwd = session.cwd
  trigger.ctx = session.ctx
  trigger.answers = session.answers
  local current = step()
  for _, spec in ipairs(checks.specs(current)) do
    if checks.evaluate(spec, trigger) then
      run_completion(current.id)
      return true
    end
  end
  return false
end

-- Manual completion (the `d` key / API). Never traps a user.
function M.done()
  if not session or advancing then
    return
  end
  run_completion(step().id)
end

function M.active()
  return session
end

-- The Ex command line just executed; feed command specs.
M._dispatch_command = function(line)
  evaluate({ command = line })
end

-- Test/driver hook: evaluate the active step against an explicit trigger.
M._evaluate = evaluate

local function ensure_hub()
  if vim.fn.exists("#tutorial_hub") == 1 then
    return
  end
  local group = vim.api.nvim_create_augroup("tutorial_hub", { clear = true })
  -- Evaluations run scheduled: rendering a card fires BufEnter, and completing
  -- a step mid-render would swap buffers under the renderer's feet.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "*",
    callback = function(args)
      vim.schedule(function()
        evaluate({ event = args.match })
      end)
    end,
  })
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = group,
    callback = function()
      local line = vim.fn.getcmdline()
      if line ~= "" then
        vim.schedule(function()
          M._dispatch_command(line)
        end)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = group,
    callback = function(args)
      vim.schedule(function()
        evaluate({ buf = args.buf })
      end)
    end,
  })
  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    callback = function()
      vim.schedule(function()
        evaluate({})
      end)
    end,
  })
end

-- Start (or resume) a tutorial by definition. Any active session is replaced.
-- Order matters: persisted answers/vars seed ctx *before* setup (so setup,
-- conds, and a steps-function can rely on prior answers), then the tour shape
-- resolves, then the resume index locates the first incomplete step.
function M.start(def)
  if session then
    M.quit(true)
  end
  local ctx, answers = M.context_for(def)
  session = {
    def = def,
    steps = {},
    index = 1,
    ctx = ctx,
    answers = answers or {},
    cwd = vim.fn.getcwd(),
    prev_win = vim.api.nvim_get_current_win(),
    entered = {}, -- steps whose enter hook already ran this session
    asked = {}, -- input steps already prompted this session
  }
  if def.setup then
    local ok, err = pcall(def.setup, session.ctx)
    if not ok then
      notify(("setup failed: %s"):format(err), vim.log.levels.ERROR)
    end
  end
  -- Resolve the tour shape now that ctx holds prior answers and setup output.
  session.steps = M.resolve_steps(def, session.ctx)
  -- A function-produced list may carry stores unknown at seed time.
  seed_answers(session.ctx, session.steps, session.answers)
  -- Resume at the first incomplete step of the resolved list.
  local _, next_id = state.progress(def, session.steps)
  if not next_id then
    notify(("Tutorial %q is already complete — reset it to replay."):format(def.title))
    local prev_win = session.prev_win
    session = nil
    -- setup ran; give teardown its matching chance to clean up.
    if def.teardown then
      pcall(def.teardown, ctx)
    end
    if prev_win and vim.api.nvim_win_is_valid(prev_win) then
      pcall(vim.api.nvim_set_current_win, prev_win)
    end
    return nil
  end
  for i, s in ipairs(session.steps) do
    if s.id == next_id then
      session.index = i
      break
    end
  end
  ensure_hub()
  present()
  -- The surface may have created windows; focus belongs to the workspace.
  if session.prev_win and vim.api.nvim_win_is_valid(session.prev_win) then
    pcall(vim.api.nvim_set_current_win, session.prev_win)
  end
  return session
end

function M.start_id(id)
  local def = registry.get(id)
  if not def then
    notify(("No tutorial registered as %q."):format(tostring(id)), vim.log.levels.WARN)
    return nil
  end
  return M.start(def)
end

-- Stop following along. Progress already earned stays earned; only this
-- tutorial's surfaces close.
-- silent=true suppresses the notification (used when switching).
function M.quit(silent)
  if not session then
    return
  end
  if vim.fn.exists("#tutorial_hub") == 1 then
    vim.api.nvim_del_augroup_by_name("tutorial_hub")
  end
  if session.def.teardown then
    pcall(session.def.teardown, session.ctx)
  end
  local was_panel = panel_mode()
  session = nil
  if was_panel then
    require("tutorial.ui.panel").close()
  else
    require("tutorial.ui.step").close()
  end
  if not silent then
    notify("Tutorial paused — progress saved. Resume with :Tutorial.")
  end
end

-- View navigation without completing: next/previous incomplete-aware.
function M.goto_step(delta)
  if not session then
    return
  end
  local target = session.index + delta
  if target < 1 or target > #session.steps then
    return
  end
  session.index = target
  present()
end

return M
