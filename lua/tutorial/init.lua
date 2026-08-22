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

local M = {}

M.register = registry.register
M.start = engine.start_id
M.active = engine.active
M.quit = engine.quit

-- setup(opts): opts.data_dir overrides where progress JSON lives (tests,
-- sandboxed profiles). Also defines the :Tutorial command.
function M.setup(opts)
  opts = opts or {}
  if opts.data_dir then
    require("tutorial.state")._set_dir(opts.data_dir)
  end

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
    if engine.active() then
      require("tutorial.ui.step").open(engine.active())
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

return M
