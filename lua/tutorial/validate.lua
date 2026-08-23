-- tutorial.validate
-- Definition checking, split by severity:
--
--   * errors   — structural problems; registry.register refuses the definition
--   * warnings — likely author mistakes worth surfacing (unknown fields,
--                malformed completion specs, dangling {answer:…} tokens)
--
-- `validate.definition(def)` returns both lists without side effects, so
-- tools (and later, machine-authored definitions) can lint before registering.
-- `assert_pure(value)` rejects anything containing a function value: it is
-- the declarative-only guard for content that arrived as data (JSON files,
-- watched inboxes) and must never smuggle executable hooks past the engine.

local checks = require("tutorial.checks")

local M = {}

local DEF_FIELDS = {
  "id",
  "title",
  "summary",
  "layout",
  "tags",
  "sections",
  "steps",
  "setup",
  "teardown",
}
local STEP_FIELDS = {
  "id",
  "title",
  "body",
  "hint",
  "recall",
  "mistake",
  "cond",
  "enter",
  "complete",
  "input",
  "completion",
}

local def_known, step_known = {}, {}
for _, f in ipairs(DEF_FIELDS) do
  def_known[f] = true
end
for _, f in ipairs(STEP_FIELDS) do
  step_known[f] = true
end

local function texts(value)
  if type(value) == "string" then
    return { value }
  end
  local out = {}
  for _, line in ipairs(type(value) == "table" and value or {}) do
    if type(line) == "string" then
      out[#out + 1] = line
    end
  end
  return out
end

-- Collect {answer:step_id} tokens and flag ones pointing nowhere.
local function check_tokens(where, lines, ids, warnings)
  for _, line in ipairs(lines) do
    for token in line:gmatch("{answer:([%w_%-]+)}") do
      if not ids[token] then
        warnings[#warnings + 1] = ("%s references {answer:%s}, but no step has that id"):format(
          where,
          token
        )
      end
    end
  end
end

local function check_completion(def_id, step_id, completion, warnings)
  if type(completion) ~= "table" then
    return
  end
  for i, spec in ipairs(completion) do
    if type(spec) == "string" then
      local ok, err = pcall(checks.parse, spec)
      if not ok then
        warnings[#warnings + 1] = ("tutorial %q step %q completion[%d]: %s"):format(
          def_id,
          step_id,
          i,
          tostring(err):gsub("^%[tutorial%.nvim%] ", "")
        )
      end
    elseif type(spec) == "table" and type(spec.context) ~= "function" then
      warnings[#warnings + 1] = ("tutorial %q step %q completion[%d] is a table without a context function"):format(
        def_id,
        step_id,
        i
      )
    end
  end
end

local function check_mistake(def_id, step_id, mistake, warnings)
  local list = mistake[1] and mistake or { mistake }
  for i, entry in ipairs(list) do
    if type(entry) ~= "table" or type(entry.match) ~= "string" then
      warnings[#warnings + 1] = ("tutorial %q step %q mistake[%d] needs a string `match`"):format(
        def_id,
        step_id,
        i
      )
    elseif entry.message ~= nil and type(entry.message) ~= "string" then
      warnings[#warnings + 1] = ("tutorial %q step %q mistake[%d].message must be a string"):format(
        def_id,
        step_id,
        i
      )
    end
  end
end

local function check_input(def_id, step_id, input, warnings)
  if input.type ~= nil and input.type ~= "text" and input.type ~= "choice" then
    warnings[#warnings + 1] = ("tutorial %q step %q input.type must be \"text\" or \"choice\""):format(
      def_id,
      step_id
    )
  end
  if input.type == "choice" and type(input.choices) ~= "table" then
    warnings[#warnings + 1] = ("tutorial %q step %q input.choices must be a list"):format(
      def_id,
      step_id
    )
  end
end

-- Structural errors (registry refuses these) plus soft warnings.
-- Returns (errors, warnings); both plain lists of human-readable strings.
function M.definition(def)
  local errors, warnings = {}, {}
  if type(def) ~= "table" then
    errors[#errors + 1] = "definition must be a table"
    return errors, warnings
  end
  if not def.id or def.id == "" then
    errors[#errors + 1] = "definition requires an id"
    return errors, warnings
  end
  local id = def.id
  if not def.title or def.title == "" then
    errors[#errors + 1] = ("definition %q requires a title"):format(id)
  end
  for field in pairs(def) do
    if not def_known[field] then
      warnings[#warnings + 1] = ("tutorial %q has unknown field %q"):format(id, field)
    end
  end
  if type(def.layout) ~= "nil" and def.layout ~= "card" and def.layout ~= "split" then
    warnings[#warnings + 1] = ("tutorial %q layout should be \"card\" or \"split\""):format(id)
  end
  if type(def.tags) ~= "nil" and type(def.tags) ~= "table" then
    warnings[#warnings + 1] = ("tutorial %q tags should be a list of strings"):format(id)
  end
  if type(def.steps) == "function" then
    -- Adaptive tours resolve their steps at start; nothing else to check yet.
    return errors, warnings
  end
  if type(def.steps) ~= "table" or #def.steps == 0 then
    errors[#errors + 1] = ("tutorial %q requires at least one step"):format(id)
    return errors, warnings
  end

  local ids, seen = {}, {}
  for i, step in ipairs(def.steps) do
    if type(step) ~= "table" then
      errors[#errors + 1] = ("tutorial %q step #%d must be a table"):format(id, i)
    else
      local sid = step.id
      if not sid or sid == "" then
        errors[#errors + 1] = ("tutorial %q step #%d requires an id"):format(id, i)
      elseif seen[sid] then
        errors[#errors + 1] = ("tutorial %q has duplicate step id %q"):format(id, sid)
      else
        seen[sid] = true
        ids[sid] = true
        if not step.title or step.title == "" then
          errors[#errors + 1] = ("tutorial %q step %q requires a title"):format(id, sid)
        end
        if not step.body or (type(step.body) == "table" and #step.body == 0) or step.body == "" then
          errors[#errors + 1] = ("tutorial %q step %q requires a body"):format(id, sid)
        end
        if step.completion ~= nil and type(step.completion) ~= "table" then
          errors[#errors + 1] = ("tutorial %q step %q completion must be a list"):format(id, sid)
        end
        if step.input ~= nil and type(step.input) ~= "table" then
          errors[#errors + 1] = ("tutorial %q step %q input must be a table"):format(id, sid)
        end
      end
    end
  end

  -- Second pass: soft checks that need the full id set (forward references
  -- in tokens are legal).
  for _, step in ipairs(def.steps) do
    if type(step) == "table" and step.id and step.title then
      local sid = step.id
      local where = ("tutorial %q step %q"):format(id, sid)
      for field in pairs(step) do
        if not step_known[field] then
          warnings[#warnings + 1] = ("%s has unknown field %q"):format(where, field)
        end
      end
      check_completion(id, sid, step.completion, warnings)
      if step.mistake ~= nil then
        check_mistake(id, sid, step.mistake, warnings)
      end
      if step.input ~= nil and type(step.input) == "table" then
        check_input(id, sid, step.input, warnings)
      end
      if step.hint ~= nil and type(step.hint) == "table" then
        for i, h in ipairs(step.hint) do
          if type(h) ~= "string" then
            warnings[#warnings + 1] = ("%s hint[%d] must be a string"):format(where, i)
          end
        end
      end
      check_tokens(("%s title"):format(where), { step.title }, ids, warnings)
      check_tokens(("%s body"):format(where), texts(step.body), ids, warnings)
      check_tokens(("%s hint"):format(where), texts(step.hint), ids, warnings)
    end
  end

  if type(def.sections) == "table" then
    local covered = {}
    for si, section in ipairs(def.sections) do
      if type(section) ~= "table" or type(section.title) ~= "string" then
        warnings[#warnings + 1] = ("tutorial %q sections[%d] needs a string title"):format(id, si)
      elseif type(section.steps) ~= "table" then
        warnings[#warnings + 1] = ("tutorial %q sections[%d] needs a steps id list"):format(id, si)
      else
        for _, sid in ipairs(section.steps) do
          if not ids[sid] then
            warnings[#warnings + 1] = ("tutorial %q section %q lists unknown step %q"):format(
              id,
              section.title,
              sid
            )
          end
          if covered[sid] then
            warnings[#warnings + 1] = ("tutorial %q step %q appears in more than one section"):format(
              id,
              sid
            )
          end
          covered[sid] = true
        end
      end
    end
  end

  return errors, warnings
end

-- Reject anything carrying function values. `path` labels the walk root in
-- the error message. Purely declarative content is what data-borne
-- definitions (JSON files, agent/inbox sources) are allowed to contain.
function M.assert_pure(value, path)
  path = path or "value"
  local seen = {}
  local function walk(node, where)
    if type(node) == "function" then
      error(("declarative-only content: function found at %s"):format(where), 0)
    end
    if type(node) ~= "table" then
      return
    end
    if seen[node] then
      return
    end
    seen[node] = true
    for key, child in pairs(node) do
      if type(key) == "function" then
        error(("declarative-only content: function key at %s"):format(where), 0)
      end
      walk(child, ("%s.%s"):format(where, tostring(key)))
    end
  end
  walk(value, path)
  return value
end

return M
