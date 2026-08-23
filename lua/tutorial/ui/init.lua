-- tutorial.ui
-- Shared rendering for tutorial scratch buffers. Lines are either plain
-- strings or tables:
--
--   { text = "...", hl = "Group" }          -- one highlighted segment
--   { segments = { { text, hl }, ... } }    -- several segments on one line

local M = {}

local config = require("tutorial.config")

local PREFIX = "tutorial://"
local NS = vim.api.nvim_create_namespace("tutorial")

-- Windows owned by tutorial surfaces, keyed by reuse key ("panel", "card",
-- "menu", "done"). Reusing a valid window is what keeps step advances from
-- stacking splits or swapping whatever buffer the user was in.
local wins = {}

-- Progress glyph by role ("done", "pending", "check"), honoring the ascii
-- preset and user overrides from setup().
function M.glyph(name)
  return config.get().glyphs[name] or ""
end

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
  -- User overrides land after the defaults so they win — and without the
  -- `default` flag, which would make Neovim keep the earlier definition.
  for name, spec in pairs(config.get().highlights or {}) do
    if type(name) == "string" and type(spec) == "table" then
      vim.api.nvim_set_hl(0, name, spec)
    end
  end
end

function M.footer(text)
  return { text = "  " .. text, hl = "TutorialMuted" }
end

-- The completion summary shared by the panel's finish view and the standalone
-- done screen (one source of truth; only the footer differs).
function M.done_lines(def, footer_text)
  return {
    { text = "" },
    { text = "  " .. M.glyph("check") .. "  TUTORIAL COMPLETE", hl = "TutorialDone" },
    { text = "" },
    {
      segments = {
        { text = "  " },
        { text = def.title, hl = "TutorialKey" },
        { text = " — all steps done." },
      },
    },
    { text = "" },
    { text = "  Progress stays saved; reset from the menu to replay.", hl = "TutorialMuted" },
    { text = "" },
    M.footer(footer_text or "[q] dismiss"),
  }
end

-- (Re)fill a buffer with entries, replacing any prior content. Clears stale
-- extmarks so re-renders never leave highlights behind.
function M.render(buf, entries)
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  local rows = {}
  for _, entry in ipairs(entries or {}) do
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
      vim.api.nvim_buf_set_extmark(buf, NS, row, mark.col, {
        end_col = mark.col + math.max(mark.len, 1),
        hl_group = mark.hl,
        priority = 50,
      })
    end
  end
  return #rows
end

-- Create (or reuse) a named scratch buffer and fill it. Returns bufnr.
function M.scratch(name, entries)
  M.setup_highlights()
  local old = vim.fn.bufnr(PREFIX .. name)
  if old ~= -1 then
    pcall(vim.api.nvim_buf_delete, old, { force = true })
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, PREFIX .. name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  M.render(buf, entries or {})
  vim.bo[buf].modified = false
  return buf
end

-- Apply the standard look and buffer-local keys to a window showing a
-- tutorial surface.
local function dress(win, buf, keys)
  vim.wo[win].spell = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = true -- visible selection on list-style buffers
  vim.wo[win].fillchars = "eob: "
  for lhs, fn in pairs(keys or {}) do
    vim.keymap.set("n", lhs, fn, { buffer = buf, silent = true, nowait = true })
  end
end

-- Display a buffer under a reuse key. When the registered window still
-- exists it is updated in place — no new split, no focus change. Otherwise a
-- window is created: a vertical dock when opts.split is set, otherwise the
-- current window is swapped.
function M.show(buf, opts)
  opts = opts or {}
  local key = opts.reuse_key
  local win = key and wins[key]
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_buf(win, buf)
    dress(win, buf, opts.keys or {})
    return buf
  end

  if opts.split then
    local cmd = opts.position == "right" and "botright" or "topleft"
    vim.cmd(cmd .. " vsplit")
    vim.cmd("vertical resize " .. math.max(opts.width or 42, 20))
  end
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  dress(win, buf, opts.keys or {})
  if key then
    wins[key] = win
  end
  return buf
end

-- Close the window registered under a reuse key, if any.
function M.close_win(key)
  local win = wins[key]
  wins[key] = nil
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

function M.win_for(key)
  local win = wins[key]
  if win and vim.api.nvim_win_is_valid(win) then
    return win
  end
end

-- Wipe every tutorial scratch buffer and forget owned windows.
function M.close_all()
  wins = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name:find(PREFIX, 1, true) == 1 then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

return M
