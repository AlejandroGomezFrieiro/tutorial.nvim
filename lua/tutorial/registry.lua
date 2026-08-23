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

local validate = require("tutorial.validate")

local M = {}

local by_id = {}
local order = {}

local function fail(msg)
  error("[tutorial.nvim] " .. msg, 0)
end

-- Register a tutorial. Re-registering the same id replaces the earlier
-- definition but keeps its position in the menu order. Structural problems
-- refuse registration; authoring lint (unknown fields, malformed specs,
-- dangling tokens) surfaces as warnings.
function M.register(def)
  local errors, warnings = validate.definition(def)
  if #errors > 0 then
    fail(errors[1])
  end
  for _, warning in ipairs(warnings) do
    vim.notify("[tutorial.nvim] " .. warning, vim.log.levels.WARN)
  end
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
