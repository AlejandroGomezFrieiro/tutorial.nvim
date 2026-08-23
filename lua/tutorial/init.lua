-- tutorial.nvim
-- A generic interactive walkthrough engine. Plugins register declarative
-- tutorials; users run :Tutorial to learn the workflow hands-on.
--
--   require("tutorial").register({ id = ..., title = ..., steps = { ... } })
--   :Tutorial              -- menu (or resume/toggle the active session)
--   :Tutorial <id>         -- start/resume a specific tutorial
--   :Tutorial focus|next|prev|goto N|status
--   :Tutorial new <id>     -- scaffold a starter file in the cwd
--   :Tutorial load <path>  -- register from a .lua / .tutorial.json file
--   :Tutorial stats [id]   -- per-step telemetry (needs analytics)
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
-- Authoring surface: lint definitions before registering, load them from
-- files (.lua full-power or .tutorial.json declarative-only).
local loader = require("tutorial.loader")
M.validate = require("tutorial.validate").definition
M.load_file = loader.load_file
M.from_json = loader.from_json

-- Read or write a free-form tour variable. Writes persist to the progress
-- file and land in ctx immediately, so predicates and copy see them; both
-- need an active session (the variable belongs to one).
function M.var(name, value)
  local session = engine.active()
  if not session then
    if value ~= nil then
      vim.notify(
        "[tutorial] Cannot store variables without an active tutorial.",
        vim.log.levels.WARN
      )
    end
    return nil
  end
  if value ~= nil then
    session.ctx[name] = value
    require("tutorial.state").set_var(session.def.id, name, value)
  end
  return session.ctx[name]
end

-- One-line status for statuslines: "Title 2/6" while a tutorial runs, nil
-- otherwise. fmt selects a variant: "percent" → "Title 33%", "step" adds the
-- current step's title.
function M.status(fmt)
  local session = engine.active()
  if not session then
    return nil
  end
  local done, total =
    select(1, require("tutorial.state").progress(session.def, session.steps)), #session.steps
  if fmt == "percent" then
    local pct = total > 0 and math.floor((done / total) * 100 + 0.5) or 0
    return ("%s %d%%"):format(session.def.title, pct)
  end
  if fmt == "step" then
    local current = session.steps[session.index]
    return ("%s · %s"):format(session.def.title, current and current.title or "")
  end
  return ("%s %d/%d"):format(session.def.title, done, total)
end

local SUBCOMMANDS = {
  "reset",
  "focus",
  "next",
  "prev",
  "goto",
  "status",
  "new",
  "load",
  "stats",
}

local function tutorial_command(args)
  local parts = vim.split(args.args, "%s+")
  local sub = args.args ~= "" and parts[1] or nil

  if sub == "reset" then
    local id = parts[2]
    if id then
      local n = require("tutorial.state").reset(id) and 1 or 0
      vim.notify(("[tutorial] Reset %d tutorial(s)."):format(n))
    else
      local n = require("tutorial.state").reset()
      vim.notify(("[tutorial] Reset %d tutorial(s)."):format(n))
    end
    return
  end

  if sub == "focus" then
    if not engine.focus() then
      vim.notify("[tutorial] Nothing to focus — start one with :Tutorial.")
    end
    return
  end

  if sub == "next" or sub == "prev" then
    engine.goto_step(sub == "next" and 1 or -1)
    return
  end

  if sub == "goto" then
    engine.goto_index(tonumber(parts[2]))
    return
  end

  if sub == "status" then
    print(("[tutorial] %s"):format(M.status() or "no active tutorial"))
    return
  end

  if sub == "new" then
    local ok, path_or_err = pcall(loader.scaffold, parts[2])
    if ok then
      vim.notify(("[tutorial] Scaffold written to %s"):format(path_or_err))
    else
      vim.notify(tostring(path_or_err), vim.log.levels.WARN)
    end
    return
  end

  if sub == "load" then
    local path = table.concat({ unpack(parts, 2) }, " ")
    local ok, def_or_err = pcall(loader.load_file, path)
    if ok then
      vim.notify(("[tutorial] Registered %q from %s"):format(def_or_err.id, path))
    else
      vim.notify(tostring(def_or_err), vim.log.levels.ERROR)
    end
    return
  end

  if sub == "stats" then
    require("tutorial.ui.stats").open(parts[2])
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
end

-- setup(opts): opts.data_dir overrides where progress JSON lives (tests,
-- sandboxed profiles); opts.panel_position / opts.panel_width configure the
-- pinned walkthrough panel; opts.poll_ms adds timer polling for state checks;
-- opts.analytics persists per-step stats; opts.ascii swaps glyph sets;
-- opts.glyphs / opts.highlights restyle surfaces. Also defines :Tutorial.
function M.setup(opts)
  opts = opts or {}
  if opts.data_dir then
    require("tutorial.state")._set_dir(opts.data_dir)
  end
  require("tutorial.config").setup(opts)

  vim.api.nvim_create_user_command("Tutorial", tutorial_command, {
    nargs = "?",
    desc = "Open the interactive tutorial menu",
    force = true, -- setup() stays idempotent across reloads
    complete = function(arglead)
      local word = vim.split(arglead, "%s+")[1] or ""
      local leading = vim.split(vim.trim(arglead), "%s+")
      -- Completing an argument to a subcommand: stay quiet.
      if #leading > 1 then
        return {}
      end
      local out = {}
      for _, name in ipairs(SUBCOMMANDS) do
        if name:find(word, 1, true) == 1 then
          out[#out + 1] = name
        end
      end
      for _, def in ipairs(registry.list()) do
        if def.id:find(word, 1, true) then
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
M._loader = loader
M._validate = require("tutorial.validate")

return M
