-- tutorial.checks
-- Completion-event evaluators. A step's `completion` list mixes string specs
-- and direct predicate tables:
--
--   "on_command:Name [args…]"   edge  — an Ex command line was executed whose
--                                     command word matches Name
--   "on_event:Pattern"          edge  — a User autocmd fired with that pattern
--   "on_buffer:pattern"         edge  — a buffer opened whose full path matches
--                                     the Lua pattern
--   "on_file_exists:glob"       state — glob expands to something
--   "on_file_contains:path:pat" state — file readable and Lua pattern found;
--                                     only the first colon splits path/pattern
--   { context = fn }            state — direct Lua predicate
--
-- Edge specs are evaluated when their hub event fires; state specs are polled
-- (CursorHold, card render, manual check). Any satisfied spec completes the
-- step.
--
-- Path/glob/pattern args resolve {ctx:field} / {answer:step_id} tokens
-- against the live session at evaluate time (never at parse time — answers
-- change between polls). Context predicates receive the session ctx as their
-- first argument; existing zero-arg predicates keep working.

local input = require("tutorial.input")

local M = {}

local cache = setmetatable({}, { __mode = "k" })

function M.parse(spec)
  if type(spec) == "table" then
    return { kind = "context", fn = spec.context }
  end
  local kind, rest = spec:match("^([%w_]+):(.+)$")
  if not kind then
    error(("[tutorial.nvim] malformed completion spec %q"):format(tostring(spec)), 0)
  end
  if kind == "on_command" then
    return { kind = "command", arg = rest }
  elseif kind == "on_event" then
    return { kind = "event", arg = rest }
  elseif kind == "on_buffer" then
    return { kind = "buffer", arg = rest }
  elseif kind == "on_file_exists" then
    return { kind = "file_exists", arg = rest }
  elseif kind == "on_file_contains" then
    -- First colon OUTSIDE {...} splits path from pattern, so tokenized paths
    -- like notes-{answer:id}.md:{ctx:word} survive intact.
    local cut, depth = nil, 0
    for i = 1, #rest do
      local c = rest:sub(i, i)
      if c == "{" then
        depth = depth + 1
      elseif c == "}" then
        depth = math.max(depth - 1, 0)
      elseif c == ":" and depth == 0 then
        cut = i
        break
      end
    end
    if not cut then
      error(("[tutorial.nvim] %s needs a path:pattern"):format(tostring(spec)), 0)
    end
    return { kind = "file_contains", path = rest:sub(1, cut - 1), pattern = rest:sub(cut + 1) }
  end
  error(("[tutorial.nvim] unknown completion spec %q"):format(tostring(spec)), 0)
end

-- Parsed specs for a step, cached against the step table itself.
function M.specs(step)
  local cached = cache[step]
  if cached then
    return cached
  end
  local out = {}
  for _, spec in ipairs(step.completion or {}) do
    out[#out + 1] = M.parse(spec)
  end
  cache[step] = out
  return out
end

-- Which hub event feeds a spec: "command", "event", "buffer", or nil for
-- polled state predicates.
function M.edge_kind(parsed)
  return parsed.kind
end

local function escape_pattern(s)
  return (s:gsub("[%c%.%+%-%*%?%[%]%(%$%^%%]", "%%%0"))
end

-- Anchor a relative path/glob to the working directory captured at session
-- start; absolute paths pass through untouched.
local function anchored(path, cwd)
  if not cwd or path:sub(1, 1) == "/" then
    return path
  end
  return cwd .. "/" .. path:gsub("^%./", "")
end

-- Interpolate session tokens into a spec arg. A token that cannot resolve
-- stays verbatim in copy, but in a matcher it means "nothing sane to match":
-- return nil so the spec reports false instead of feeding broken text to
-- expand()/glob().
local function resolved(text, ctx, answers)
  local out = input.interpolate(text, ctx, answers)
  if type(out) ~= "string" or out:find("{ctx:", 1, true) or out:find("{answer:", 1, true) then
    return nil
  end
  return out
end

-- Interpolate, expand (~, env vars), and anchor to the session cwd. Nil when
-- anything along the way is unresolvable.
local function expanded(text, ctx, answers, cwd)
  local value = resolved(text, ctx, answers)
  if not value then
    return nil
  end
  local ok, out = pcall(vim.fn.expand, value)
  if not ok then
    return nil
  end
  return anchored(out, cwd)
end

-- Evaluate one parsed spec. `trigger` carries optional event payload:
--   trigger.command — the executed Ex command line (command specs)
--   trigger.event   — the fired User pattern (event specs)
--   trigger.ctx     — the session context (token interpolation, predicates)
--   trigger.answers — per-step answers (answer-token interpolation)
function M.evaluate(parsed, trigger)
  trigger = trigger or {}
  local ctx, answers = trigger.ctx, trigger.answers
  local kind = parsed.kind
  if kind == "command" then
    local line = trigger.command
    if not line then
      return false
    end
    -- Match the leading command word; trailing args are allowed.
    return line:find("^%s*" .. escape_pattern(parsed.arg) .. "%s") ~= nil
      or line:find("^%s*" .. escape_pattern(parsed.arg) .. "%s*$") ~= nil
  elseif kind == "event" then
    return trigger.event ~= nil and trigger.event == parsed.arg
  elseif kind == "buffer" then
    local pattern = resolved(parsed.arg, ctx, answers)
    if not pattern then
      return false
    end
    local name = vim.api.nvim_buf_get_name(trigger.buf or 0)
    return name ~= "" and name:find(pattern) ~= nil
  elseif kind == "file_exists" then
    local glob = expanded(parsed.arg, ctx, answers, trigger.cwd)
    return glob ~= nil and #vim.fn.glob(glob, false, true) > 0
  elseif kind == "file_contains" then
    local path = expanded(parsed.path, ctx, answers, trigger.cwd)
    if not path or vim.fn.filereadable(path) ~= 1 then
      return false
    end
    local pattern = resolved(parsed.pattern, ctx, answers)
    if not pattern then
      return false
    end
    for _, line in ipairs(vim.fn.readfile(path)) do
      if line:find(pattern) then
        return true
      end
    end
    return false
  elseif kind == "context" then
    if type(parsed.fn) ~= "function" then
      return false
    end
    local ok, res = pcall(parsed.fn, ctx)
    return ok and res ~= nil and res ~= false
  end
  return false
end

return M
