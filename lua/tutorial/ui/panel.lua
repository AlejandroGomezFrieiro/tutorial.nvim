-- tutorial.ui.panel
-- The pinned walkthrough panel: one docked window per session, updated in
-- place. Opening and advancing never moves the user's focus; the workspace
-- keeps its window, cursor, and mode while steps check off beside it.

local config = require("tutorial.config")
local engine = require("tutorial.engine")
local state = require("tutorial.state")
local ui = require("tutorial.ui")

local M = {}

local st = {} -- { winid, bufnr, session, done }

local function cfg()
  return config.get()
end

function M.bar(session)
  local def = session.def
  local steps = session.steps
  local glyphs = {}
  for _, step in ipairs(steps) do
    glyphs[#glyphs + 1] = state.is_done(def.id, step.id) and "✦" or "✧"
  end
  return {
    segments = {
      { text = "  " .. table.concat(glyphs, "") .. " ", hl = "TutorialAccent" },
      { text = ("%d/%d"):format(state.progress(def, steps), #steps), hl = "TutorialKey" },
    },
  }
end

-- Completion summary shown inside the panel when the tutorial finishes.
function M.done_lines(def)
  return {
    { text = "" },
    { text = "  ✓  TUTORIAL COMPLETE", hl = "TutorialDone" },
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
    ui.footer("[q] dismiss"),
  }
end

local function entries()
  if st.done then
    return M.done_lines(st.session.def)
  end
  local step = require("tutorial.ui.step")
  return step.lines(st.session, { panel = true })
end

local function attach_keys(buf)
  local function rerender()
    ui.render(st.bufnr, entries())
    vim.bo[st.bufnr].modified = false
  end
  local keys = {
    n = function()
      if not st.done then
        engine.goto_step(1)
      end
    end,
    p = function()
      if not st.done then
        engine.goto_step(-1)
      end
    end,
    h = function()
      -- step.lua owns show_hint for its own rendering path.
      local step = require("tutorial.ui.step")
      step.toggle_hint()
      rerender()
    end,
    a = function()
      if not st.done then
        engine.answer()
      end
    end,
    r = function()
      if not st.done then
        engine.answer()
      end
    end,
    d = function()
      if not st.done then
        engine.done()
      end
    end,
    s = function()
      M.hide()
    end,
    q = function()
      if st.done then
        M.dismiss()
      else
        engine.quit()
      end
    end,
  }
  for lhs, fn in pairs(keys) do
    vim.keymap.set("n", lhs, fn, { buffer = buf, silent = true, nowait = true })
  end
end

local function ensure_buffer()
  if st.bufnr and vim.api.nvim_buf_is_valid(st.bufnr) then
    ui.render(st.bufnr, entries())
    vim.bo[st.bufnr].modified = false
    return
  end
  st.bufnr = ui.scratch("panel", entries())
  attach_keys(st.bufnr)
end

local function ensure_window(session)
  if st.winid and vim.api.nvim_win_is_valid(st.winid) then
    return
  end
  local conf = cfg()
  vim.cmd((conf.panel_position == "right" and "botright" or "topleft") .. " vsplit")
  vim.cmd("vertical resize " .. math.max(conf.panel_width or 42, 20))
  st.winid = vim.api.nvim_get_current_win()
  vim.wo[st.winid].spell = false
  vim.wo[st.winid].number = false
  vim.wo[st.winid].relativenumber = false
  vim.wo[st.winid].signcolumn = "no"
  vim.wo[st.winid].cursorline = true
  vim.wo[st.winid].fillchars = "eob: "
  vim.api.nvim_win_set_buf(st.winid, st.bufnr)
  -- Creating the split moved focus; give it straight back.
  if session.prev_win and vim.api.nvim_win_is_valid(session.prev_win) then
    pcall(vim.api.nvim_set_current_win, session.prev_win)
  end
end

-- Show (or silently refresh) the panel for a session.
function M.open(session)
  st.session = session
  st.done = state.progress(session.def, session.steps) >= #session.steps
  ensure_buffer()
  ensure_window(session)
end

-- Render the completion summary in place of the step card; stays visible
-- until dismissed.
function M.finish(def)
  st.session = { def = def }
  st.done = true
  ensure_buffer()
  ensure_window(st.session)
end

function M.update(session)
  st.session = session
  st.done = false
  if not M.visible() then
    M.open(session)
    return
  end
  ensure_buffer()
end

function M.visible()
  return st.winid ~= nil
    and vim.api.nvim_win_is_valid(st.winid)
    and vim.api.nvim_win_get_buf(st.winid) == st.bufnr
end

-- The panel's backing buffer (tests, embedders).
function M.buffer()
  return st.bufnr
end

-- Hide without ending the session; :Tutorial or s brings it back.
function M.hide()
  if st.winid and vim.api.nvim_win_is_valid(st.winid) then
    pcall(vim.api.nvim_win_close, st.winid, true)
  end
end

function M.toggle(session)
  if M.visible() then
    M.hide()
  else
    M.open(session or st.session)
  end
end

-- Focus the panel deliberately (the only way d/n/p/h are reachable).
function M.focus()
  if M.visible() then
    vim.api.nvim_set_current_win(st.winid)
    return true
  end
  return false
end

-- Dismiss the completion summary and close the panel.
function M.dismiss()
  M.close()
end

-- Tear down completely (session ended or quit).
function M.close()
  st.done = nil
  st.session = nil
  if st.winid and vim.api.nvim_win_is_valid(st.winid) then
    pcall(vim.api.nvim_win_close, st.winid, true)
  end
  if st.bufnr and vim.api.nvim_buf_is_valid(st.bufnr) then
    pcall(vim.api.nvim_buf_delete, st.bufnr, { force = true })
  end
  st.winid, st.bufnr = nil, nil
end

return M
