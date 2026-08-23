-- tutorial.state
-- Sticky, persistent progress. Completion is write-once: an event can check a
-- step off, only `reset` un-checks it (the VS Code walkthrough model).
--
-- Layout: <data_dir>/<tutorial-id>.json →
--   { version = 1,                               -- schema version
--     done = { [step_id] = os.time() },          -- write-once completions
--     answers = { [step_id] = value },           -- input-step captures
--     vars = { [key] = value },                  -- free-form tour variables
--     stats = { [step_id] = {...} } }            -- opt-in timing/hint usage
-- Answers and vars are re-writable (re-answering overwrites); only `reset`
-- clears them. The data dir defaults to stdpath("data")/tutorial and can be
-- overridden via setup({ data_dir = ... }) or _set_dir() in tests.

local M = {}

local VERSION = 1

M._set_dir = function(dir)
  data_dir = dir
end

local function dir()
  if data_dir then
    return data_dir
  end
  data_dir = vim.fn.stdpath("data") .. "/tutorial"
  return data_dir
end

local function path(id)
  return dir() .. "/" .. id .. ".json"
end

local function blank()
  return { version = VERSION, done = {}, answers = {}, vars = {}, stats = {} }
end

local function read(id)
  if vim.fn.filereadable(path(id)) ~= 1 then
    return blank()
  end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path(id)), "\n"))
  if not ok or type(data) ~= "table" then
    return blank()
  end
  -- Older files predate the version field; everything here is additive.
  data.version = data.version or VERSION
  data.done = data.done or {}
  data.answers = data.answers or {}
  data.vars = data.vars or {}
  data.stats = data.stats or {}
  return data
end

local function write(id, data)
  vim.fn.mkdir(dir(), "p")
  data.version = VERSION
  local lines = { vim.json.encode(data) }
  vim.fn.writefile(lines, path(id))
end

function M.load(id)
  return read(id)
end

-- True when any sticky progress exists for the tutorial.
function M.has_progress(id)
  return vim.fn.filereadable(path(id)) == 1
end

function M.is_done(id, step_id)
  return read(id).done[step_id] ~= nil
end

-- Mark a step complete. Sticky: later calls are no-ops.
function M.mark_done(id, step_id)
  local data = read(id)
  if data.done[step_id] then
    return false
  end
  data.done[step_id] = os.time()
  write(id, data)
  return true
end

-- Number of completed steps and the id of the first incomplete step.
-- Returns (done_count, next_step_id or nil when finished). `steps` overrides
-- def.steps — callers with an active session pass the resolved (cond-
-- filtered, possibly function-produced) list so counts match what renders.
function M.progress(def, steps)
  local done = read(def.id).done
  local count = 0
  local next_id
  for _, step in ipairs(steps or def.steps) do
    if done[step.id] then
      count = count + 1
    elseif not next_id then
      next_id = step.id
    end
  end
  return count, next_id
end

-- Answers: input-step captures keyed by step id. Re-answering overwrites.
function M.set_answer(id, step_id, value)
  local data = read(id)
  data.answers[step_id] = value
  write(id, data)
end

function M.answer(id, step_id)
  return read(id).answers[step_id]
end

-- Vars: free-form tutorial variables keyed by name. Re-setting overwrites.
function M.set_var(id, key, value)
  local data = read(id)
  data.vars[key] = value
  write(id, data)
end

function M.get_var(id, key)
  return read(id).vars[key]
end

-- Stats: opt-in per-step telemetry (elapsed seconds, hint presses). Written
-- when a step completes; only `reset` clears them.
function M.set_stats(id, step_id, stat)
  local data = read(id)
  data.stats[step_id] = stat
  write(id, data)
end

function M.stats(id)
  return read(id).stats or {}
end

-- Timestamp of the most recent completion, or nil for untouched tours.
-- The menu uses this to show how stale a finished tour is.
function M.last_done_at(id)
  local latest
  for _, ts in pairs(read(id).done) do
    if latest == nil or ts > latest then
      latest = ts
    end
  end
  return latest
end

-- Reset one tutorial, or every tutorial when id is nil.
function M.reset(id)
  if id then
    if vim.fn.filereadable(path(id)) == 1 then
      vim.fn.delete(path(id))
      return true
    end
    return false
  end
  local removed = 0
  for _, file in ipairs(vim.fn.glob(dir() .. "/*.json", false, true)) do
    vim.fn.delete(file)
    removed = removed + 1
  end
  return removed
end

return M
