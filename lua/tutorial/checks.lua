-- tutorial.checks
-- Completion-event evaluators. A step's `completion` list mixes string specs
-- and direct predicate tables:
--
--   "on_command:Name [args…]"    edge  — an Ex command line was executed whose
--                                      command word matches Name
--   "on_command:Name!"           edge  — same, but the command must also have
--                                      run without setting v:errmsg
--   "on_event:Pattern"           edge  — a User autocmd fired with that
--                                      pattern (* and ? act as globs)
--   "on_buffer:pattern"          edge  — a buffer opened whose full path
--                                      matches the Lua pattern
--   "on_key:<lhs>"               edge  — the user typed the key sequence
--                                      (fed by the engine's key listener)
--   "on_file_exists:glob"        state — glob expands to something
--   "on_file_contains:path:pat"  state — some path:pattern split along the
--                                      colons finds a readable file whose
--                                      content matches the Lua pattern
--   "on_buf_contains:pattern"    state — the current buffer contains a line
--                                      matching the Lua pattern
--   "on_diagnostic:<severity>"   state — no diagnostics of that severity
--                                      (default error) remain in the buffer
--   { context = fn }             state — direct Lua predicate
--
-- Edge specs are evaluated when their hub event fires; state specs are polled
-- (CursorHold, timer tick, card render, manual check). Any satisfied spec
-- completes the step.
--
-- Path/glob/pattern args resolve {ctx:field} / {answer:step_id} tokens
-- against the live session at evaluate time (never at parse time — answers
-- change between polls). Context predicates receive the session ctx as their
-- first argument; existing zero-arg predicates keep working.

local input = require("tutorial.input")

local M = {}

local cache = setmetatable({}, { __mode = "k" })

local SEVERITIES = { error = 1, warn = 2, info = 3, hint = 4 }

local function split_kind(spec)
  local kind, rest = spec:match("^([%w_]+):(.+)$")
  if not kind then
    error(("[tutorial.nvim] malformed completion spec %q"):format(tostring(spec)), 0)
  end
  return kind, rest
end

function M.parse(spec)
  if type(spec) == "table" then
    return { kind = "context", fn = spec.context }
  end
  local kind, rest = split_kind(spec)
  if kind == "on_command" then
    -- Trailing ! demands a clean run: v:errmsg must not have moved while the
    -- command executed.
    local strict = rest:sub(-1) == "!"
    return { kind = "command", arg = strict and rest:sub(1, -2) or rest, strict = strict }
  elseif kind == "on_event" then
    return { kind = "event", arg = rest }
  elseif kind == "on_buffer" then
    return { kind = "buffer", arg = rest }
  elseif kind == "on_key" then
    -- Normalize notation ("<leader>x", "<CR>", …) into raw bytes once; the
    -- key listener sees raw bytes too. `raw` keeps the original spelling so
    -- feeds that pass literal notation (tests, scripted drivers) match too.
    local ok, seq = pcall(vim.api.nvim_replace_termcodes, rest, true, true, true)
    return { kind = "key", arg = ok and seq or rest, raw = rest }
  elseif kind == "on_file_exists" then
    return { kind = "file_exists", arg = rest }
  elseif kind == "on_file_contains" then
    -- Every colon OUTSIDE {...} is a candidate path/pattern split, tried left
    -- to right until one yields a readable matching file. Paths containing
    -- colons therefore survive; tokens like notes-{answer:id}.md:{ctx:word}
    -- survive too.
    local cuts, depth = {}, 0
    for i = 1, #rest do
      local c = rest:sub(i, i)
      if c == "{" then
        depth = depth + 1
      elseif c == "}" then
        depth = math.max(depth - 1, 0)
      elseif c == ":" and depth == 0 then
        cuts[#cuts + 1] = i
      end
    end
    if #cuts == 0 then
      error(("[tutorial.nvim] %s needs a path:pattern"):format(tostring(spec)), 0)
    end
    return { kind = "file_contains", cuts = cuts, text = rest }
  elseif kind == "on_buf_contains" then
    return { kind = "buf_contains", arg = rest }
  elseif kind == "on_diagnostic" then
    local level = SEVERITIES.error
    if rest ~= "" then
      level = SEVERITIES[rest:lower()]
      if not level then
        error(("[tutorial.nvim] unknown diagnostic severity %q"):format(rest), 0)
      end
    end
    return { kind = "diagnostic", level = level }
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

-- True when the step carries at least one spec of the given kind. Lets the
-- engine skip work (key listening) steps cannot use.
function M.has_kind(step, kind)
  for _, parsed in ipairs(M.specs(step)) do
    if parsed.kind == kind then
      return true
    end
  end
  return false
end

local function escape_pattern(s)
  return (s:gsub("[%c%.%+%-%*%?%[%]%(%$%^%%]", "%%%0"))
end

-- Glob-style matching for User event names: `*` matches anything, `?` one
-- character, everything else literally. A pattern without wildcards keeps
-- its exact-match behavior.
local function glob_pattern(glob)
  local out = glob:gsub("[%c%.%+%-%*%?%[%]%(%$%^%%]", function(c)
    if c == "*" then
      return ".*"
    elseif c == "?" then
      return "."
    end
    return "%" .. c
  end)
  return "^" .. out .. "$"
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

-- The leading command word of an executed Ex line; the engine's mistake
-- matching compares against this.
function M.leading_word(line)
  return (line:match("^%s*(%S+)") or "")
end

local function buf_lines(buf)
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf or 0, 0, -1, false)
  if not ok then
    return ""
  end
  return table.concat(lines, "\n")
end

-- True when the buffer has no diagnostics of severity `level` or worse
-- (error=1 … hint=4). Errors in the diagnostic machinery count as "not done"
-- — never fatal.
local function diagnostics_clear(buf, level)
  local ok, counts = pcall(vim.diagnostic.count, buf or 0)
  if not ok or type(counts) ~= "table" then
    return false
  end
  for sev = 1, level do
    if (counts[sev] or 0) > 0 then
      return false
    end
  end
  return true
end

-- True when the recent keystroke buffer ends with the given byte sequence.
local function ends_with(keys, seq)
  if #seq == 0 then
    return false
  end
  local tail = table.concat(keys):sub(-#seq)
  return tail == seq
end

-- Key specs match either the termcode-normalized sequence (what a real
-- terminal feeds) or the literal notation (scripted feeds).
local function key_hit(parsed, keys)
  return ends_with(keys, parsed.arg) or (parsed.raw ~= nil and ends_with(keys, parsed.raw))
end

-- Evaluate one parsed spec. `trigger` carries optional event payload:
--   trigger.command       — the executed Ex command line (command specs)
--   trigger.errmsg_changed— v:errmsg moved during it (strict commands)
--   trigger.event         — the fired User pattern (event specs)
--   trigger.keys          — recent keystrokes, oldest first (key specs)
--   trigger.buf           — the buffer entered/saved (buffer/state specs)
--   trigger.ctx           — the session context (token interpolation)
--   trigger.answers       — per-step answers (answer-token interpolation)
function M.evaluate(parsed, trigger)
  trigger = trigger or {}
  local ctx, answers = trigger.ctx, trigger.answers
  local kind = parsed.kind
  if kind == "command" then
    local line = trigger.command
    if not line then
      return false
    end
    -- Match the leading command phrase; trailing args are allowed, and a
    -- longer command sharing the prefix ("Story ideas" vs "Story idea")
    -- never matches.
    local matched = line:find("^%s*" .. escape_pattern(parsed.arg) .. "%s") ~= nil
      or line:find("^%s*" .. escape_pattern(parsed.arg) .. "%s*$") ~= nil
    if not matched then
      return false
    end
    if parsed.strict then
      return trigger.errmsg_changed == false
    end
    return true
  elseif kind == "event" then
    return trigger.event ~= nil and trigger.event:find(glob_pattern(parsed.arg)) ~= nil
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
    for _, cut in ipairs(parsed.cuts) do
      local path = expanded(parsed.text:sub(1, cut - 1), ctx, answers, trigger.cwd)
      if path and vim.fn.filereadable(path) == 1 then
        local pattern = resolved(parsed.text:sub(cut + 1), ctx, answers)
        if pattern then
          for _, line in ipairs(vim.fn.readfile(path)) do
            if line:find(pattern) then
              return true
            end
          end
        end
      end
    end
    return false
  elseif kind == "buf_contains" then
    local pattern = resolved(parsed.arg, ctx, answers)
    if not pattern then
      return false
    end
    return buf_lines(trigger.buf):find(pattern) ~= nil
  elseif kind == "diagnostic" then
    return diagnostics_clear(trigger.buf, parsed.level)
  elseif kind == "key" then
    return type(trigger.keys) == "table" and key_hit(parsed, trigger.keys) or false
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
