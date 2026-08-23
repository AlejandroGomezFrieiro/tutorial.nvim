-- tutorial.ui.stats
-- Opt-in analytics, rendered: per-step time spent, hint presses, and mistake
-- hits, straight out of the progress JSON (:Tutorial stats [id]). Authors use
-- it to find where learners stall; nothing ever leaves the machine.

local config = require("tutorial.config")
local registry = require("tutorial.registry")
local state = require("tutorial.state")
local ui = require("tutorial.ui")

local M = {}

function M.open(id)
  if not config.get().analytics then
    vim.notify(
      "[tutorial] Analytics are off — enable them with setup({ analytics = true }).",
      vim.log.levels.WARN
    )
    return
  end
  id = id or (require("tutorial.engine").active() or {}).def.id
  local def = id and registry.get(id) or nil
  if not def then
    vim.notify("[tutorial] No tutorial to show stats for.", vim.log.levels.WARN)
    return
  end

  local stats = state.stats(def.id)
  local entries = {
    { text = "  " .. ui.glyph("check") .. "  STEP STATS", hl = "TutorialTitle" },
    {
      segments = {
        { text = "  " },
        { text = def.title, hl = "TutorialKey" },
        { text = "  (time · hints · mistakes)" },
      },
      hl = "TutorialMuted",
    },
    { text = "" },
  }
  local rows = 0
  for _, step in ipairs(type(def.steps) == "table" and def.steps or {}) do
    local stat = stats[step.id]
    if stat then
      rows = rows + 1
      entries[#entries + 1] = {
        segments = {
          { text = "  " .. step.title, hl = "TutorialKey" },
          { text = ("  %ds"):format(stat.secs or 0), hl = "TutorialAccent" },
          { text = ("  · %d hints"):format(stat.hints or 0), hl = "TutorialMuted" },
          { text = ("  · %d mistakes"):format(stat.mistakes or 0), hl = "TutorialMuted" },
        },
      }
    end
  end
  if rows == 0 then
    entries[#entries + 1] = {
      text = "  No telemetry yet — finish some steps first.",
      hl = "TutorialMuted",
    }
  end
  entries[#entries + 1] = { text = "" }
  entries[#entries + 1] = ui.footer("q close")

  local buf = ui.scratch("stats", entries)
  ui.show(buf, { reuse_key = "stats" })
  vim.keymap.set("n", "q", function()
    ui.close_win("stats")
  end, { buffer = buf, silent = true })
end

return M
