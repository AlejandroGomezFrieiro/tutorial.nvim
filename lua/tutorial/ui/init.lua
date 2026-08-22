-- tutorial.ui
-- Minimal scratch-buffer renderer shared by the menu, step card, and done
-- screens. Lines are either plain strings or segment tables:
--
--   { segments = { { text = "...", hl = "TutorialKey" }, ... } }

local M = {}

local PREFIX = "tutorial://"

function M.hl(name, link)
  vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", { default = true }, link))
end

function M.setup_highlights()
  M.hl("TutorialTitle", { link = "Title" })
  M.hl("TutorialKey", { link = "Directory", bold = true })
  M.hl("TutorialMuted", { link = "Comment" })
  M.hl("TutorialDone", { link = "String" })
  M.hl("TutorialAccent", { link = "Special" })
  M.hl("TutorialCardMeta", { link = "Comment", italic = true })
end

function M.footer(text)
  return { text = "  " .. text, hl = "TutorialMuted" }
end

-- Render one line entry into buffer lines + extmark highlights. Entries are a
-- string, a `{ text, hl }` shorthand, or a `{ segments }` table.
local function put(buf, rows, entry)
  if type(entry) == "string" then
    entry = { text = entry }
  end
  local segments = entry.segments or { entry }
  local texts, marks = {}, {}
  local col = 0
  for _, seg in ipairs(segments) do
    texts[#texts + 1] = seg.text
    if seg.hl then
      marks[#marks + 1] = { col = col, len = #(seg.text or ""), hl = seg.hl }
    end
    col = col + #(seg.text or "")
  end
  local line = table.concat(texts, "")
  vim.api.nvim_buf_set_lines(buf, #rows, #rows, false, { line })
  rows[#rows + 1] = true
  local row = #rows - 1
  for _, mark in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, vim.api.nvim_create_namespace("tutorial"), row, mark.col, {
      end_col = mark.col + math.max(mark.len, 1),
      hl_group = mark.hl,
      priority = 50,
    })
  end
end

-- Create (or reuse) a named scratch buffer and fill it. Returns bufnr.
function M.scratch(name, entries)
  M.setup_highlights()
  local buf = vim.fn.bufnr(PREFIX .. name)
  if buf ~= -1 then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, PREFIX .. name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true

  local rows = {}
  for _, entry in ipairs(entries or {}) do
    put(buf, rows, entry)
  end
  vim.bo[buf].modified = false
  return buf
end

-- Display a scratch buffer in the current window (or a vertical split when
-- requested), focus it, and attach buffer-local keymaps.
function M.show(buf, opts)
  opts = opts or {}
  if opts.split then
    vim.cmd("vertical leftabove split")
    vim.cmd("vertical resize " .. math.max(opts.width or 42, 20))
  end
  vim.api.nvim_win_set_buf(0, buf)
  vim.wo.spell = false
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = "no"
  vim.wo.cursorline = true -- visible selection on list-style buffers
  vim.wo.fillchars = "eob: "
  for lhs, fn in pairs(opts.keys or {}) do
    vim.keymap.set("n", lhs, fn, { buffer = buf, silent = true, nowait = true })
  end
  return buf
end

-- Wipe every tutorial scratch buffer (quit paths).
function M.close_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name:find(PREFIX, 1, true) == 1 then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

return M
