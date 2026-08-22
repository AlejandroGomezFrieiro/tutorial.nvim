-- tutorial.ui.step
-- Step-card content shared by the pinned panel and the full-window card, plus
-- the legacy full-window presentation (layout = "card"). Copy resolves
-- {ctx:…}/{answer:…} tokens against the live session before rendering.

local engine = require("tutorial.engine")
local input = require("tutorial.input")
local state = require("tutorial.state")
local ui = require("tutorial.ui")

local M = {}

local show_hint = false

-- Hint visibility is shared between the full-window card and the panel.
function M.toggle_hint()
  show_hint = not show_hint
end

-- Render `{key:X}` tokens as highlighted key hints. `X` containing spaces is
-- prose (a description), not a keymap name, and renders muted instead.
local function key_segments(text)
  local segments = {}
  local pos = 1
  while true do
    local s, e, token = text:find("{key:([^}]*)}", pos)
    if not s then
      if pos <= #text then
        segments[#segments + 1] = { text = text:sub(pos) }
      end
      break
    end
    if s > pos then
      segments[#segments + 1] = { text = text:sub(pos, s - 1) }
    end
    local is_prose = token:find("%s") ~= nil
    -- Adaptive display: when a mapping exists for a plain lhs, mark it live.
    local mapped = not is_prose and vim.fn.mapcheck(token, "n") ~= "" or false
    segments[#segments + 1] = {
      text = token,
      hl = is_prose and "TutorialMuted" or (mapped and "TutorialDone" or "TutorialKey"),
    }
    pos = e + 1
  end
  return { segments = segments }
end

-- Progress glyphs and counts over the session's resolved step list (cond-
-- skipped steps are neither rendered nor counted).
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

-- The card content for the current step of a session. opts.panel adds the
-- [s]hide hint used by the pinned panel.
function M.lines(session, opts)
  opts = opts or {}
  local def = session.def
  local ctx, answers = session.ctx, session.answers
  local step = session.steps[session.index]
  local entries = {
    { text = "  ✦  " .. string.upper(def.title), hl = "TutorialTitle" },
    M.bar(session),
    {
      segments = {
        { text = ("  Step %d — "):format(session.index), hl = "TutorialAccent" },
        { text = input.interpolate(step.title, ctx, answers), hl = "TutorialKey" },
      },
    },
    { text = "" },
  }
  local body = type(step.body) == "string" and { step.body } or step.body
  for _, line in ipairs(body) do
    entries[#entries + 1] = type(line) == "string"
        and key_segments("  " .. input.interpolate(line, ctx, answers))
      or line
  end
  if show_hint and step.hint then
    entries[#entries + 1] = { text = "" }
    entries[#entries + 1] = {
      text = "  Hint: " .. input.interpolate(step.hint, ctx, answers),
      hl = "TutorialCardMeta",
    }
  end
  entries[#entries + 1] = { text = "" }
  entries[#entries + 1] = ui.footer(
    "[n]ext [p]rev [h]int"
      .. (step.input and " [a]nswer" or "")
      .. " d(one)"
      .. (opts.panel and " [s]hide" or "")
      .. " q(uit)"
  )
  return entries
end

-- Full-window presentation (layout = "card"). Reuses its window so advances
-- never stack splits.
function M.open(session)
  local buf = ui.scratch("step", M.lines(session))
  local keys = {
    n = function()
      show_hint = false
      engine.goto_step(1)
    end,
    p = function()
      show_hint = false
      engine.goto_step(-1)
    end,
    h = function()
      show_hint = not show_hint
      M.open(session)
    end,
    a = function()
      engine.answer()
    end,
    r = function()
      -- Re-answer: same prompt, stored value overwritten.
      engine.answer()
    end,
    d = function()
      show_hint = false
      engine.done()
    end,
    q = function()
      show_hint = false
      engine.quit()
    end,
  }
  -- Keymaps attach before display: showing the buffer can fire BufEnter, and
  -- a same-tick completion must never find this buffer half-initialized.
  for lhs, fn in pairs(keys) do
    vim.keymap.set("n", lhs, fn, { buffer = buf, silent = true, nowait = true })
  end
  ui.show(buf, { reuse_key = "card" })
end

function M.close()
  show_hint = false
  ui.close_win("card")
end

return M
