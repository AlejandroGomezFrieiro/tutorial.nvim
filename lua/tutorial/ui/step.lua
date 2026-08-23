-- tutorial.ui.step
-- Step-card content shared by the pinned panel and the full-window card, plus
-- the legacy full-window presentation (layout = "card"). Copy resolves
-- {ctx:…}/{answer:…} tokens against the live session before rendering.
--
-- Pedagogy in the render layer: hint ladders reveal one nudge at a time,
-- recall steps keep their {key:…} tokens masked until attempted/revealed, and
-- author-declared mistakes surface as a gentle note — never an advance.

local engine = require("tutorial.engine")
local input = require("tutorial.input")
local state = require("tutorial.state")
local ui = require("tutorial.ui")

local M = {}

-- Hint visibility lives on the session (per step), shared between the
-- full-window card and the panel. Each press climbs one rung of the ladder.
function M.toggle_hint()
  return engine.cycle_hint()
end

-- Render `{key:X}` tokens as highlighted key hints. `X` containing spaces is
-- prose (a description), not a keymap name, and renders muted instead.
-- `masked` replaces every token with a neutral placeholder: recall steps hide
-- the literal answer until the learner tries (or asks).
local function key_segments(text, masked)
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
    if masked then
      segments[#segments + 1] = { text = "[hidden]", hl = "TutorialMuted" }
    else
      local is_prose = token:find("%s") ~= nil
      -- Adaptive display: when a mapping exists for a plain lhs, mark it live.
      local mapped = not is_prose and vim.fn.mapcheck(token, "n") ~= "" or false
      segments[#segments + 1] = {
        text = token,
        hl = is_prose and "TutorialMuted" or (mapped and "TutorialDone" or "TutorialKey"),
      }
    end
    pos = e + 1
  end
  return { segments = segments }
end

-- Progress glyphs and counts over the session's resolved step list (cond-
-- skipped steps are neither rendered nor counted). Done and pending get
-- distinct faces so the shape of progress reads at a glance.
function M.bar(session)
  local def = session.def
  local steps = session.steps
  local segments = {}
  for _, s in ipairs(steps) do
    local done = state.is_done(def.id, s.id)
    segments[#segments + 1] = {
      text = ui.glyph(done and "done" or "pending"),
      hl = done and "TutorialDone" or "TutorialMuted",
    }
  end
  segments[#segments + 1] = {
    text = string.format(" %d/%d", state.progress(def, steps), #steps),
    hl = "TutorialKey",
  }
  return { segments = segments }
end

local function hint_list(step)
  if type(step.hint) == "table" then
    return step.hint
  end
  return step.hint and { step.hint } or {}
end

-- The card content for the current step of a session. opts.panel adds the
-- [s]hide hint used by the pinned panel.
function M.lines(session, opts)
  opts = opts or {}
  local def = session.def
  local ctx, answers = session.ctx, session.answers
  local step = session.steps[session.index]
  local hints = hint_list(step)
  local shown_hints = session.hints[step.id] or 0
  local masked = step.recall == true and not engine.revealed(step.id)
  local entries = {
    { text = "  " .. ui.glyph("done") .. "  " .. string.upper(def.title), hl = "TutorialTitle" },
    M.bar(session),
  }
  local section = engine.section_of(def, step.id)
  if section then
    entries[#entries + 1] = {
      segments = {
        { text = "  [" },
        { text = section, hl = "TutorialAccent" },
        { text = "]" },
      },
      hl = "TutorialMuted",
    }
  end
  entries[#entries + 1] = {
    segments = {
      { text = ("  Step %d — "):format(session.index), hl = "TutorialAccent" },
      { text = input.interpolate(step.title, ctx, answers), hl = "TutorialKey" },
    },
  }
  entries[#entries + 1] = { text = "" }
  local body = type(step.body) == "string" and { step.body } or step.body
  for _, line in ipairs(body) do
    entries[#entries + 1] = type(line) == "string"
        and key_segments("  " .. input.interpolate(line, ctx, answers), masked)
      or line
  end
  for i = 1, shown_hints do
    entries[#entries + 1] = {
      text = ("  Hint (%d/%d): %s"):format(i, #hints, input.interpolate(hints[i], ctx, answers)),
      hl = "TutorialCardMeta",
    }
  end
  if session.mistake then
    entries[#entries + 1] = {
      segments = {
        { text = "  ! ", hl = "TutorialAccent" },
        { text = session.mistake, hl = "TutorialCardMeta" },
      },
    }
  end
  entries[#entries + 1] = { text = "" }
  local footer = "[n]ext [p]rev"
  if masked then
    footer = footer .. " [h]eveal"
  elseif #hints > 0 then
    if #hints > 1 then
      footer = footer .. (" [h]int (%d/%d)"):format(shown_hints, #hints)
    else
      footer = footer .. " [h]int"
    end
  end
  if step.input then
    footer = footer .. " [a]nswer"
  end
  footer = footer .. " d(one)" .. (opts.panel and " [s]hide" or "") .. " q(uit)"
  entries[#entries + 1] = ui.footer(footer)
  return entries
end

-- Full-window presentation (layout = "card"). Reuses its window so advances
-- never stack splits.
function M.open(session)
  local buf = ui.scratch("step", M.lines(session))
  local keys = {
    n = function()
      engine.goto_step(1)
    end,
    p = function()
      engine.goto_step(-1)
    end,
    h = function()
      engine.cycle_hint()
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
      engine.done()
    end,
    q = function()
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
  ui.close_win("card")
end

return M
