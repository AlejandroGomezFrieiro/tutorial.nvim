-- tutorial.nvim
-- A generic interactive walkthrough engine. Plugins register declarative
-- tutorials; users run :Tutorial to learn the workflow hands-on.
--
--   require("tutorial").register({ id = ..., title = ..., steps = { ... } })
--   :Tutorial              -- menu (or resume the active session)
--   :Tutorial <id>         -- start/resume a specific tutorial
--   :Tutorial reset [id]   -- forget progress

local registry = require("tutorial.registry")
local engine = require("tutorial.engine")
local input = require("tutorial.input")

local M = {}

M.register = registry.register
M.start = engine.start_id
M.active = engine.active
M.quit = engine.quit
-- Ergonomic helpers for adaptive tours: slug names for paths, and the input
-- surface (capture) plus {ctx:…}/{answer:…} interpolation.
M.slug = input.slug
M.interpolate = input.interpolate
M.input = input

-- One-line status for statuslines: "Title 2/6" while a tutorial runs, nil
-- otherwise.
function M.status()
  local session = engine.active()
  if not session then
    return nil
  end
  local done = select(1, require("tutorial.state").progress(session.def, session.steps))
  return ("%s %d/%d"):format(session.def.title, done, #session.steps)
end

-- setup(opts): opts.data_dir overrides where progress JSON lives (tests,
-- sandboxed profiles); opts.panel_position / opts.panel_width configure the
-- pinned walkthrough panel. Also defines the :Tutorial command.
function M.setup(opts)
  opts = opts or {}
  if opts.data_dir then
    require("tutorial.state")._set_dir(opts.data_dir)
  end
  require("tutorial.config").setup(opts)

  vim.api.nvim_create_user_command("Tutorial", function(args)
    local sub = args.args ~= "" and vim.split(args.args, "%s+")[1] or nil
    if sub == "reset" then
      local id = vim.split(args.args, "%s+")[2]
      if id then
        local n = require("tutorial.state").reset(id) and 1 or 0
        vim.notify(("[tutorial] Reset %d tutorial(s)."):format(n))
      else
        local n = require("tutorial.state").reset()
        vim.notify(("[tutorial] Reset %d tutorial(s)."):format(n))
      end
      return
    end
    if sub then
      M.start(sub)
      return
    end
    local active = engine.active()
    if active then
      -- Re-invoking while running focuses (or toggles) the pinned panel;
      -- card-mode tutorials re-open their card instead.
      if active.def.layout == "card" then
        require("tutorial.ui.step").open(active)
      else
        require("tutorial.ui.panel").toggle(active)
      end
      return
    end
    require("tutorial.ui.menu").open()
  end, {
    nargs = "?",
    desc = "Open the interactive tutorial menu",
    force = true, -- setup() stays idempotent across reloads
    complete = function(arglead)
      local out = { "reset" }
      for _, def in ipairs(registry.list()) do
        if arglead == "" or def.id:find(arglead, 1, true) then
          out[#out + 1] = def.id
        end
      end
      return out
    end,
  })

  return M
end

-- Test hooks.
M._registry = registry
M._engine = engine
M._state = require("tutorial.state")
M._checks = require("tutorial.checks")
M._config = require("tutorial.config")
M._input = input

return M
