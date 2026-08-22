-- tutorial.registry
-- Holds tutorial definitions contributed by plugins. A definition:
--
--   {
--     id = "my-plugin-basics",          -- required, unique
--     title = "Getting started",        -- required
--     summary = "One line for menus",   -- optional
--     layout = "card" | "split",        -- optional step display (default card)
--     setup = function(ctx) ... end,    -- optional workspace prep; ctx persists
--     teardown = function(ctx) ... end, -- optional cleanup on quit/finish
--     steps = {                         -- required list — or a function
--                                       -- (ctx) -> list, resolved at start
--       {
--         id = "first-thing",           -- required, unique within tutorial
--         title = "Do the thing",       -- required
--         body = { "line", ... },       -- string or line list (required)
--         hint = "Extra nudge",         -- optional, shown on h
--         cond = function(ctx) ... end, -- optional; false skips the step
--         enter = function(ctx) ... end,    -- optional, once on first present
--         complete = function(ctx) ... end, -- optional, when checked off
--         input = {                     -- optional ask-the-user step:
--           question = "...", type = "text" | "choice", choices = {...},
--           default = ..., store = "ctx_key", validate = fn, transform = fn,
--         },
--         completion = {                -- optional; any match completes the
--           "on_command:MyThing",       --   step. Strings per checks.parse,
--           { context = function() ... end },  -- or direct predicates.
--         },
--       },
--     },
--   }

local M = {}

local by_id = {}
local order = {}

local function fail(msg)
  error("[tutorial.nvim] " .. msg, 0)
end

local function validate(def)
  if type(def) ~= "table" then
    fail("definition must be a table")
  end
  if not def.id or def.id == "" then
    fail("definition requires an id")
  end
  if not def.title or def.title == "" then
    fail(("definition %q requires a title"):format(def.id))
  end
  if type(def.steps) == "function" then
    -- Adaptive tours resolve their steps at start; nothing to check yet.
    return
  end
  if type(def.steps) ~= "table" or #def.steps == 0 then
    fail(("tutorial %q requires at least one step"):format(def.id))
  end
  local seen = {}
  for i, step in ipairs(def.steps) do
    if type(step) ~= "table" then
      fail(("tutorial %q step #%d must be a table"):format(def.id, i))
    end
    if not step.id or step.id == "" then
      fail(("tutorial %q step #%d requires an id"):format(def.id, i))
    end
    if seen[step.id] then
      fail(("tutorial %q has duplicate step id %q"):format(def.id, step.id))
    end
    seen[step.id] = true
    if not step.title or step.title == "" then
      fail(("tutorial %q step %q requires a title"):format(def.id, step.id))
    end
    if not step.body or (type(step.body) == "table" and #step.body == 0) or step.body == "" then
      fail(("tutorial %q step %q requires a body"):format(def.id, step.id))
    end
    if step.completion ~= nil and type(step.completion) ~= "table" then
      fail(("tutorial %q step %q completion must be a list"):format(def.id, step.id))
    end
    if step.input ~= nil and type(step.input) ~= "table" then
      fail(("tutorial %q step %q input must be a table"):format(def.id, step.id))
    end
  end
end

-- Register a tutorial. Re-registering the same id replaces the earlier
-- definition but keeps its position in the menu order.
function M.register(def)
  validate(def)
  if not by_id[def.id] then
    order[#order + 1] = def.id
  end
  by_id[def.id] = def
  return def
end

function M.get(id)
  return by_id[id]
end

-- All registered definitions in registration order.
function M.list()
  local out = {}
  for _, id in ipairs(order) do
    out[#out + 1] = by_id[id]
  end
  return out
end

-- Test hook: drop everything.
function M._clear()
  by_id = {}
  order = {}
end

return M
