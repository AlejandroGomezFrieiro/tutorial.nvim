-- tutorial.ui.menu
-- The :Tutorial landing screen: every registered tutorial with its progress.
-- Counts come from each definition's resolved step list, so adaptive tours
-- (steps-as-function, cond) display honest totals.
--
-- Grows with the catalog: `/` filters by substring (id, title, tags), tags
-- show inline, finished tours report how long ago they were completed, and a
-- mouse click lands the cursor on a row.

local engine = require("tutorial.engine")
local registry = require("tutorial.registry")
local state = require("tutorial.state")
local ui = require("tutorial.ui")

local M = {}

local filter_text

local function matches(def, needle)
  if needle == "" then
    return true
  end
  local haystacks = { def.id, def.title or "" }
  for _, tag in ipairs(def.tags or {}) do
    haystacks[#haystacks + 1] = tostring(tag)
  end
  for _, text in ipairs(haystacks) do
    if text:lower():find(needle:lower(), 1, true) then
      return true
    end
  end
  return false
end

-- Status segments for one definition: not started / in progress / complete,
-- with staleness ("· 12d ago") on finished tours.
local function status_segments(def, done_count, total)
  local out = {}
  if total == 0 then
    out[1] = { text = "not started", hl = "TutorialMuted" }
  elseif done_count >= total then
    local ts = state.last_done_at(def.id)
    local days = ts and math.floor((os.time() - ts) / 86400) or nil
    out[1] = { text = ui.glyph("check") .. " complete", hl = "TutorialDone" }
    out[2] = {
      text = days and (days <= 0 and " · today" or (" · %dd ago"):format(days)) or "",
      hl = "TutorialMuted",
    }
  elseif done_count > 0 then
    out[1] = { text = "in progress", hl = "TutorialAccent" }
  else
    out[1] = { text = "not started", hl = "TutorialMuted" }
  end
  return out
end

function M.open()
  local defs = registry.list()
  if #defs == 0 then
    vim.notify("[tutorial] No tutorials registered yet.", vim.log.levels.WARN)
    return
  end
  filter_text = filter_text or ""

  -- Entries append one buffer line each; record which line selects what.
  local entries = {
    { text = "  " .. ui.glyph("done") .. "  TUTORIALS", hl = "TutorialTitle" },
  }
  if filter_text ~= "" then
    entries[#entries + 1] = {
      segments = {
        { text = "  filter: " },
        { text = filter_text, hl = "TutorialAccent" },
        { text = "  ([/] to edit)" },
      },
      hl = "TutorialMuted",
    }
  end
  entries[#entries + 1] = { text = "" }
  local select = {}
  local first_row
  local shown = 0
  for _, def in ipairs(defs) do
    if matches(def, filter_text) then
      shown = shown + 1
      -- Resolve per definition: steps may be a function of persisted ctx,
      -- and cond-skipped steps do not count toward the total.
      local steps = engine.resolve_steps(def, engine.context_for(def))
      local done_count = state.progress(def, steps)

      select[#entries + 1] = def
      if not first_row then
        first_row = #entries + 1 -- the row the title line is about to occupy
      end
      local row = {
        segments = {
          { text = ("  %d. "):format(shown), hl = "TutorialMuted" },
          { text = def.title, hl = "TutorialKey" },
          { text = ("  (%d/%d)"):format(done_count, #steps), hl = "TutorialMuted" },
        },
      }
      for _, seg in ipairs(status_segments(def, done_count, #steps)) do
        row.segments[#row.segments + 1] = seg
      end
      if def.tags and #def.tags > 0 then
        row.segments[#row.segments + 1] = {
          text = ("  [%s]"):format(table.concat(vim.tbl_map(tostring, def.tags), "/")),
          hl = "TutorialCardMeta",
        }
      end
      entries[#entries + 1] = row

      if def.summary then
        -- The summary line belongs to the same tutorial.
        select[#entries + 1] = def
        entries[#entries + 1] = { text = "     " .. def.summary, hl = "TutorialCardMeta" }
      end
    end
  end
  if shown == 0 then
    entries[#entries + 1] = { text = "  (nothing matches this filter)", hl = "TutorialMuted" }
  end
  entries[#entries + 1] = { text = "" }
  entries[#entries + 1] = ui.footer("<CR> start/resume   / filter   r reset   q close")

  local buf = ui.scratch("menu", entries)
  ui.show(buf)

  -- Land on the first selectable row so <CR> works immediately.
  vim.api.nvim_win_set_cursor(0, { first_row or 1, 0 })

  local function row_def()
    return select[vim.api.nvim_win_get_cursor(0)[1]]
  end

  local function start_here()
    local def = row_def()
    if def then
      require("tutorial.engine").start(def)
    end
  end

  vim.keymap.set("n", "<CR>", start_here, { buffer = buf, silent = true })
  vim.keymap.set("n", "<LeftMouse>", function()
    local pos = vim.fn.getmousepos()
    if pos.line > 0 then
      pcall(
        vim.api.nvim_win_set_cursor,
        0,
        { math.min(pos.line, vim.api.nvim_buf_line_count(buf)), 0 }
      )
    end
  end, { buffer = buf, silent = true })
  vim.keymap.set("n", "<2-LeftMouse>", start_here, { buffer = buf, silent = true })
  vim.keymap.set("n", "/", function()
    local answer = vim.fn.input("Filter tutorials: ", filter_text or "")
    vim.cmd("redraw")
    filter_text = answer ~= "" and answer or nil
    M.open()
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

-- Test hook: preset the filter without driving the input prompt.
function M._set_filter(text)
  filter_text = text
end

return M
