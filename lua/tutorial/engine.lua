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

local registry = require("tutorial.registry")
local state = require("tutorial.state")
local checks = require("tutorial.checks")

local M = {}

local session -- { def, index, ctx, group } or nil
local advancing -- guards against re-entrant evaluation while a completion is
-- being processed (rendering the next card fires BufEnter, which would
-- otherwise evaluate again and delete the buffer mid-render)

local function step()
  if not session then
    return nil
  end
  return session.def.steps[session.index]
end

local function notify(msg, level)
  vim.notify("[tutorial] " .. msg, level or vim.log.levels.INFO)
end

local ui ---@type table lazy-required on first render to break load cycles

local function finish_step(step_id)
  state.mark_done(session.def.id, step_id)
  local done_count = select(1, state.progress(session.def))
  notify(("✓ %s (%d/%d)"):format(step().title, done_count, #session.def.steps))
  if done_count >= #session.def.steps then
    if session.def.teardown then
      pcall(session.def.teardown, session.ctx)
    end
    local def = session.def
    session = nil
    vim.api.nvim_del_augroup_by_name("tutorial_hub")
    require("tutorial.ui.done").open(def)
    return
  end
  -- Advance to the next incomplete step.
  for i, s in ipairs(session.def.steps) do
    if not state.is_done(session.def.id, s.id) then
      session.index = i
      break
    end
  end
  ui = ui or require("tutorial.ui.step")
  ui.open(session)
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
-- state predicates are always polled.
local function evaluate(trigger)
  if not session or advancing then
    return false
  end
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
function M.start(def)
  if session then
    M.quit(true)
  end
  session = {
    def = def,
    index = 1,
    ctx = {},
    group = nil,
  }
  if def.setup then
    local ok, err = pcall(def.setup, session.ctx)
    if not ok then
      notify(("setup failed: %s"):format(err), vim.log.levels.ERROR)
    end
  end
  -- Resume at the first incomplete step.
  local _, next_id = state.progress(def)
  for i, s in ipairs(def.steps) do
    if s.id == next_id then
      session.index = i
      break
    end
  end
  if not next_id then
    notify(("Tutorial %q is already complete — reset it to replay."):format(def.title))
    session = nil
    return nil
  end
  ensure_hub()
  ui = ui or require("tutorial.ui.step")
  ui.open(session)
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

-- Stop following along. Progress already earned stays earned.
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
  session = nil
  require("tutorial.ui.step").close()
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
  if target < 1 or target > #session.def.steps then
    return
  end
  session.index = target
  ui = ui or require("tutorial.ui.step")
  ui.open(session)
end

return M
