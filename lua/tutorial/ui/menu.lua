-- tutorial.ui.menu
-- The :Tutorial landing screen: every registered tutorial with its progress.

local registry = require("tutorial.registry")
local state = require("tutorial.state")
local ui = require("tutorial.ui")

local M = {}

function M.open()
  local defs = registry.list()
  if #defs == 0 then
    vim.notify("[tutorial] No tutorials registered yet.", vim.log.levels.WARN)
    return
  end

  -- Entries append one buffer line each; record which line selects what.
  local entries = {
    { text = "  ✦  TUTORIALS", hl = "TutorialTitle" },
    { text = "" },
  }
  local select = {}
  local first_row
  for i, def in ipairs(defs) do
    local done_count, next_id = state.progress(def)
    local status
    if not next_id then
      status = { text = "✓ complete", hl = "TutorialDone" }
    elseif done_count > 0 then
      status = { text = "in progress", hl = "TutorialAccent" }
    else
      status = { text = "not started", hl = "TutorialMuted" }
    end

    select[#entries + 1] = def
    if not first_row then
      first_row = #entries + 1 -- the row the title line is about to occupy
    end
    entries[#entries + 1] = {
      segments = {
        { text = ("  %d. "):format(i), hl = "TutorialMuted" },
        { text = def.title, hl = "TutorialKey" },
        { text = ("  (%d/%d) "):format(done_count, #def.steps), hl = "TutorialMuted" },
        status,
      },
    }

    if def.summary then
      -- The summary line belongs to the same tutorial.
      select[#entries + 1] = def
      entries[#entries + 1] = { text = "     " .. def.summary, hl = "TutorialCardMeta" }
    end
  end
  entries[#entries + 1] = { text = "" }
  entries[#entries + 1] = ui.footer("<CR> start/resume   r reset   q close")

  local buf = ui.scratch("menu", entries)
  ui.show(buf)

  -- Land on the first selectable row so <CR> works immediately.
  vim.api.nvim_win_set_cursor(0, { first_row or 1, 0 })

  local function row_def()
    return select[vim.api.nvim_win_get_cursor(0)[1]]
  end

  vim.keymap.set("n", "<CR>", function()
    local def = row_def()
    if def then
      require("tutorial.engine").start(def)
    end
  end, { buffer = buf, silent = true })
  vim.keymap.set("n", "r", function()
    local def = row_def()
    if not def then
      return
    end
    if vim.fn.confirm(("Reset progress for %q?"):format(def.title), "&Reset\n&Cancel", 2) == 1 then
      state.reset(def.id)
      M.open()
    end
  end, { buffer = buf, silent = true })
  vim.keymap.set("n", "q", function()
    ui.close_all()
  end, { buffer = buf, silent = true })
end

return M
