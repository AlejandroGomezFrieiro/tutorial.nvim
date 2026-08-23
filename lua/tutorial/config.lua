-- tutorial.config
-- User-facing defaults. setup(opts) merges on top; nothing here is required.
-- Unknown options and bad values warn instead of failing: a typo'd option in
-- a config file should be visible, never silently swallowed.

local M = {}

local GLYPHS = { done = "✦", pending = "✧", check = "✓" }
local GLYPHS_ASCII = { done = "*", pending = "-", check = "x" }

local function defaults()
  return {
    -- The pinned walkthrough panel docked beside the workspace while a
    -- tutorial runs.
    panel_position = "left", -- "left" | "right"
    panel_width = 42,
    -- Poll interval (ms) for state predicates while a session is active.
    -- 0 (default) keeps the classic event/CursorHold cadence; a positive
    -- value makes {context = fn}-style checks track reality even while the
    -- user sits in insert mode.
    poll_ms = 0,
    -- Persist per-step timing and hint-usage into the progress JSON, for
    -- :Tutorial stats. Off by default; purely local when on.
    analytics = false,
    -- Render progress glyphs as plain ASCII ("*", "-", "x") for terminals
    -- without Unicode support. An explicit `glyphs` table always wins.
    ascii = false,
    -- Progress glyphs used across panel/card/menu/done surfaces.
    glyphs = vim.deepcopy(GLYPHS),
    -- Highlight overrides applied after the defaults: each entry is a table
    -- passed straight to nvim_set_hl (e.g. { link = "Title" } or
    -- { fg = "#ff0000", bold = true }).
    highlights = {},
  }
end

local KNOWN = {
  data_dir = "string",
  panel_position = { left = true, right = true },
  panel_width = "number",
  poll_ms = "number",
  analytics = "boolean",
  ascii = "boolean",
  glyphs = "table",
  highlights = "table",
}

function M.defaults()
  return defaults()
end

options = nil
local auto_glyphs = false -- true while `glyphs` was set by the ascii preset

local function warn(msg)
  vim.notify("[tutorial] " .. msg, vim.log.levels.WARN)
end

local function validate(key, value)
  local rule = KNOWN[key]
  if not rule then
    return ("ignoring unknown setup option %q"):format(key)
  end
  if type(rule) == "string" and type(value) ~= rule then
    return ("setup option %q must be a %s"):format(key, rule)
  end
  if key == "panel_position" and not rule[value] then
    return ([[panel_position must be "left" or "right" (got %q)]]):format(tostring(value))
  end
  if key == "poll_ms" and value < 0 then
    return "poll_ms must be >= 0"
  end
  if key == "glyphs" then
    for _, field in ipairs({ "done", "pending", "check" }) do
      if type(value[field]) ~= "string" then
        return ("glyphs.%s must be a string"):format(field)
      end
    end
  end
end

-- Merge user opts over fresh defaults (repeatable). Returns the merged table.
function M.setup(opts)
  opts = opts or {}
  if not options then
    options = M.defaults()
  end
  -- The ascii preset swaps the glyph set; an explicit glyphs table wins.
  if opts.ascii == true and opts.glyphs == nil then
    opts = vim.tbl_extend("force", {}, opts, { glyphs = vim.deepcopy(GLYPHS_ASCII) })
    auto_glyphs = true
  elseif opts.ascii == false and auto_glyphs and opts.glyphs == nil then
    opts = vim.tbl_extend("force", {}, opts, { glyphs = vim.deepcopy(GLYPHS) })
    auto_glyphs = false
  end
  for key, value in pairs(opts) do
    local problem = validate(key, value)
    if problem then
      warn(problem)
    else
      options[key] = value
    end
  end
  return options
end

function M.get()
  if not options then
    options = M.defaults()
  end
  return options
end

-- Test hook: forget everything (options are module state).
M._reset = function()
  options = nil
  auto_glyphs = false
end

return M
