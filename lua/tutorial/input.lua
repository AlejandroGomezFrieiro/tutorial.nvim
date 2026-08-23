-- tutorial.input
-- The ask side of interactive walkthroughs: a first-class prompt surface for
-- `input` steps, plus the text helpers answers feed ({ctx:…}/{answer:…}
-- interpolation and slug()).
--
-- Calm by construction: prompts draw on the command line and never move
-- window focus. Cancelling is always allowed — capture returns nil and the
-- answer stays unset; `d` still completes the step (never trap the user).
-- Capture-once is owned by the engine, never a polled predicate.

local M = {}

-- Sentinel returned by the driver when the user aborted (<Esc>/<C-C>). A
-- printable token: NUL cannot survive the command line, and typing this
-- string by accident is not a real risk.
local CANCELLED = "@@TUTORIAL_CANCELLED@@"

-- The capture primitive: one prompt, raw result. Overridable in tests.
--   spec.type == "text"  → vim.fn.input with question/default
--   spec.type == "choice"→ vim.fn.inputlist over spec.choices
M._driver = function(spec)
  if spec.type == "choice" then
    local lines = { (spec.question or "Choose one") .. ":" }
    local values = {}
    for _, choice in ipairs(spec.choices or {}) do
      values[#values + 1] = tostring(choice)
      lines[#lines + 1] = ("  %d. %s"):format(#values, choice)
    end
    local pick = vim.fn.inputlist(lines)
    if pick < 1 or pick > #values then
      return CANCELLED
    end
    return values[pick]
  end
  return vim.fn.input({
    prompt = (spec.question or "Answer") .. ": ",
    default = spec.default,
    cancelreturn = CANCELLED,
  })
end

-- URL-ish identifier: ASCII alphanumerics kept, every other run collapses to
-- a single dash, edges trimmed. "Ada Lovelace!" → "ada-lovelace". Authors who
-- need different rules own `transform`; this is just the convenient default.
function M.slug(value)
  value = tostring(value or ""):lower()
  value = value:gsub("[%c%s_]+", "-")
  value = value:gsub("[^%w%-]+", "-")
  value = value:gsub("^%-+", ""):gsub("%-+$", "")
  return value
end

-- Render `{ctx:field}` / `{answer:step_id}` tokens from a session context and
-- its per-step answers. Unknown fields stay verbatim so a copy typo is
-- visible, never silent; other tokens (`{key:X}`, prose) pass through.
function M.interpolate(text, ctx, answers)
  if type(text) ~= "string" then
    return text
  end
  return (
    text:gsub("{(%w+:[^}]*)}", function(token)
      local kind, name = token:match("^(%w+):(.+)$")
      local source = kind == "ctx" and ctx or kind == "answer" and answers or nil
      local value = source and source[name]
      if value ~= nil then
        return tostring(value)
      end
      return nil -- keep the token verbatim
    end)
  )
end

-- One captured value through transform → pattern → validate.
-- validate returns true, false/nil (generic error), or an error string.
-- `pattern` is the declarative sibling of a validate function (it is what
-- data-only definitions can carry): a Lua pattern the answer must match.
-- Returns (value, nil) when acceptable, (nil, err) otherwise.
local function normalize(spec, raw)
  local value = raw
  if type(spec.transform) == "function" then
    local ok, transformed = pcall(spec.transform, value)
    if not ok then
      return nil, ("transform failed: %s"):format(tostring(transformed))
    end
    value = transformed
  end
  if type(value) == "string" and type(spec.pattern) == "string" then
    if value:find(spec.pattern) == nil then
      return nil, type(spec.message) == "string" and spec.message or "invalid input"
    end
  end
  if type(spec.validate) == "function" then
    local ok, res = pcall(spec.validate, value)
    if not ok then
      return nil, ("invalid input: %s"):format(tostring(res))
    end
    if res == false or res == nil then
      return nil, "invalid input"
    end
    if type(res) == "string" and res ~= "" then
      return nil, res
    end
  end
  return value, nil
end

-- Prompt until the answer passes validate, or until the user cancels out.
-- Returns the normalized value, or nil when cancelled (answer left unset).
function M.capture(spec)
  spec = spec or {}
  while true do
    local raw = M._driver(spec)
    if raw == CANCELLED or raw == nil then
      return nil
    end
    local value, err = normalize(spec, raw)
    if not err then
      return value
    end
    pcall(vim.api.nvim_err_writeln, "[tutorial.nvim] " .. err)
  end
end

return M
