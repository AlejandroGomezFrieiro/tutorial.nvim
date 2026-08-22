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
    local path, pattern = rest:match("^([^:]+):(.+)$")
    if not path then
      error(("[tutorial.nvim] %s needs a path:pattern"):format(tostring(spec)), 0)
    end
    return { kind = "file_contains", path = path, pattern = pattern }
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

-- Evaluate one parsed spec. `trigger` carries optional event payload:
--   trigger.command — the executed Ex command line (command specs)
--   trigger.event   — the fired User pattern (event specs)
function M.evaluate(parsed, trigger)
  trigger = trigger or {}
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
    local name = vim.api.nvim_buf_get_name(trigger.buf or 0)
    return name ~= "" and name:find(parsed.arg) ~= nil
  elseif kind == "file_exists" then
    return #vim.fn.glob(vim.fn.expand(parsed.arg), false, true) > 0
  elseif kind == "file_contains" then
    local path = vim.fn.expand(parsed.path)
    if vim.fn.filereadable(path) ~= 1 then
      return false
    end
    for _, line in ipairs(vim.fn.readfile(path)) do
      if line:find(parsed.pattern) then
        return true
      end
    end
    return false
  elseif kind == "context" then
    if type(parsed.fn) ~= "function" then
      return false
    end
    local ok, res = pcall(parsed.fn)
    return ok and res ~= nil and res ~= false
  end
  return false
end

return M
