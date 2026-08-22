-- tutorial.config
-- User-facing defaults. setup(opts) merges on top; nothing here is required.

local M = {}

local DEFAULTS = {
  -- The pinned walkthrough panel docked beside the workspace while a
  -- tutorial runs.
  panel_position = "left", -- "left" | "right"
  panel_width = 42,
}

function M.defaults()
  return vim.deepcopy(DEFAULTS)
end

local options = M.defaults()

-- Merge user opts over the current options (repeatable).
function M.setup(opts)
  opts = opts or {}
  for key, value in pairs(opts) do
    if DEFAULTS[key] ~= nil then
      options[key] = value
    end
  end
end

function M.get()
  return options
end

return M
