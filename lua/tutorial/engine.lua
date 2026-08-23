-- tutorial.engine
-- Runs one active tutorial session and owns the single autocmd hub that feeds
-- the current step's completion checks. Tutorials never attach their own
-- autocmds; everything flows through here.
--
-- Hub events and what they feed:
--   User *        → on_event edge specs (glob patterns allowed)
--   CmdlineEnter  → snapshots v:errmsg so command specs can demand success
--   CmdlineLeave  → on_command edge specs (via getcmdline()) + mistake checks
--   BufEnter      → on_buffer edge specs + state poll
--   BufWritePost  → state poll
--   CursorHold    → state poll
--   optional timer→ state poll every config.poll_ms while active
--   typed keys    → on_key edge specs + mistake checks (single engine-owned
--                   vim.on_key listener; never a per-tutorial one)
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
local config = require("tutorial.config")

local M = {}

local session -- { def, steps, index, ctx, answers, cwd, prev_win, entered,
-- asked, hints, revealed, keys, stats, mistake, last_id, cmd_err0 } or nil
local advancing -- guards against re-entrant evaluation while a completion is
-- being processed (rendering the next card fires BufEnter, which would
-- otherwise evaluate again and delete the buffer mid-render)
-- Mutually recursive trio: present schedules input capture, capture nudges
-- evaluation, evaluation advances and presents again.
local present, ask_current, evaluate

local poll_timer -- uv timer backing config.poll_ms, when enabled
local key_ns = vim.api.nvim_create_namespace("tutorial_keys")

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

local function rerender()
  if not session then
    return
  end
  if panel_mode() then
    require("tutorial.ui.panel").update(session)
  else
    require("tutorial.ui.step").open(session)
  end
end

-- Title of the section containing step_id, or nil. Sections group long tours
-- into chunks; membership is declared once on the definition.
function M.section_of(def, step_id)
  for _, section in ipairs(def.sections or {}) do
    for _, sid in ipairs(section.steps or {}) do
      if sid == step_id then
        return section.title
      end
    end
  end
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
  -- A fresh step forgets the previous step's corrective note.
  if session.last_id ~= current.id then
    session.mistake = nil
    session.last_id = current.id
  end
  -- Analytics clock starts on first presentation.
  if session.stats[current.id] == nil then
    session.stats[current.id] = { t0 = os.time(), hints = 0 }
  end
  if type(current.enter) == "function" and not session.entered[current.id] then
    session.entered[current.id] = true
    local ok, err = pcall(current.enter, session.ctx)
    if not ok then
      notify(("step enter failed: %s"):format(err), vim.log.levels.ERROR)
    end
  end
  rerender()
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

-- Hint ladder: each press advances through the hint list, wrapping to hidden.
-- Fading support on demand instead of dumping every hint at once. Returns the
-- level now shown (1-based) or 0 when fully hidden again.
function M.cycle_hint()
  if not session then
    return nil
  end
  local current = step()
  if not current then
    return nil
  end
  local total = type(current.hint) == "table" and #current.hint or (current.hint and 1 or 0)
  if total == 0 then
    return 0
  end
  local level = (session.hints[current.id] or 0) + 1
  if level > total then
    level = 0
  end
  session.hints[current.id] = level
  -- Revealing a recall-masked step is what the same key is for.
  if level > 0 then
    session.revealed[current.id] = true
  end
  if config.get().analytics then
    session.stats[current.id].hints = session.stats[current.id].hints + 1
  end
  return level
end

-- Whether the current step's key hints may render unmasked yet. Recall steps
-- mask {key:…} tokens until the learner attempts/reveals — retrieval before
-- the answer, the point of the exercise.
function M.revealed(step_id)
  return session == nil or session.revealed[step_id or (step() or {}).id] ~= nil
end

-- Show a gentle corrective note without advancing. Matched against the
-- leading command word (commands) or the recent keystroke tail (keys).
local function flag_mistake(message)
  if not session then
    return
  end
  session.mistake = message or "Not quite — check the step again."
  if config.get().analytics then
    local stat = session.stats[step().id]
    stat.mistakes = (stat.mistakes or 0) + 1
  end
  rerender()
end

local function mistake_entries(current)
  if not current or not current.mistake then
    return {}
  end
  return current.mistake[1] and current.mistake or { current.mistake }
end

-- The Ex command line just executed; check mistakes first (a wrong command is
-- the teaching moment), then completion specs.
M._dispatch_command = function(line, errmsg_changed)
  if not session or advancing then
    return
  end
  local word = checks.leading_word(line)
  for _, entry in ipairs(mistake_entries(step())) do
    if entry.match == word then
      flag_mistake(entry.message)
      return
    end
  end
  evaluate({ command = line, errmsg_changed = errmsg_changed })
end

-- Feed raw keystrokes from the engine-owned listener. Keys accumulate in a
-- bounded buffer for the whole session so late-appearing on_key specs still
-- see history.
M._feed_key = function(chunk)
  if not session or advancing then
    return
  end
  -- The command line (prompts, ":" commands) has its own paths.
  if vim.fn.mode() == "c" then
    return
  end
  local keys = session.keys
  keys[#keys + 1] = chunk
  if #keys > 32 then
    table.remove(keys, 1)
  end
  local current = step()
  local key_specs = checks.has_kind(current, "key")
  for _, entry in ipairs(mistake_entries(current)) do
    if type(entry.match) == "string" and #entry.match > 0 then
      local ok, seq = pcall(vim.api.nvim_replace_termcodes, entry.match, true, true, true)
      local tail = table.concat(keys)
      -- Match the literal notation or its termcode form (see checks.key_hit).
      if tail:sub(-#entry.match) == entry.match or (ok and #seq > 0 and tail:sub(-#seq) == seq) then
        flag_mistake(entry.message)
        return
      end
    end
  end
  if key_specs then
    evaluate({ keys = keys })
  end
end

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
  -- Persist opt-in telemetry alongside the completion timestamp.
  if config.get().analytics then
    local stat = session.stats[step_id]
    if stat then
      stat.completed_at = os.time()
      stat.secs = os.time() - (stat.t0 or os.time())
      state.set_stats(session.def.id, step_id, {
        secs = stat.secs,
        hints = stat.hints,
        mistakes = stat.mistakes or 0,
      })
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
    M._stop_hubs()
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

-- Test/driver hook: evaluate the active step against an explicit trigger.
M._evaluate = evaluate

local function start_poll_timer()
  local interval = config.get().poll_ms or 0
  if interval <= 0 or poll_timer then
    return
  end
  poll_timer = vim.loop.new_timer()
  poll_timer:start(
    interval,
    interval,
    vim.schedule_wrap(function()
      evaluate({})
    end)
  )
end

local function ensure_key_listener()
  if vim.on_key then
    vim.on_key(function(chunk)
      M._feed_key(chunk)
    end, key_ns)
  end
end

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
  vim.api.nvim_create_autocmd("CmdlineEnter", {
    group = group,
    callback = function()
      if session then
        session.cmd_err0 = vim.v.errmsg
      end
    end,
  })
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = group,
    callback = function()
      local line = vim.fn.getcmdline()
      local changed = session ~= nil and vim.v.errmsg ~= session.cmd_err0
      if line ~= "" then
        vim.schedule(function()
          M._dispatch_command(line, changed)
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
  ensure_key_listener()
  start_poll_timer()
end

-- Tear down every observer the hub installed (autocmds, key listener, poll
-- timer). Idempotent; called by quit and by natural completion.
function M._stop_hubs()
  if vim.fn.exists("#tutorial_hub") == 1 then
    vim.api.nvim_del_augroup_by_name("tutorial_hub")
  end
  if vim.on_key then
    pcall(vim.on_key, nil, key_ns)
  end
  if poll_timer then
    pcall(function()
      poll_timer:stop()
      poll_timer:close()
    end)
    poll_timer = nil
  end
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
    hints = {}, -- hint-ladder level currently shown, per step
    revealed = {}, -- recall steps whose keys have been uncovered
    keys = {}, -- bounded recent-keystroke buffer
    stats = {}, -- per-step analytics accumulators
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
  M._stop_hubs()
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

-- Jump straight to the nth visible step (clamped). Backs :Tutorial goto N.
function M.goto_index(n)
  if not session or type(n) ~= "number" then
    return
  end
  n = math.max(1, math.min(n, #session.steps))
  session.index = n
  present()
end

-- Bring the tutorial surface forward deliberately (:Tutorial focus).
function M.focus()
  if not session then
    return false
  end
  if panel_mode() then
    return require("tutorial.ui.panel").focus()
  end
  local win = require("tutorial.ui").win_for("card")
  if win then
    vim.api.nvim_set_current_win(win)
    return true
  end
  -- Card closed: reopen it where the user stands.
  require("tutorial.ui.step").open(session)
  return true
end

-- Test hook: the uv timer backing config.poll_ms (nil when not polling).
function M._poll_timer()
  return poll_timer
end

return M
