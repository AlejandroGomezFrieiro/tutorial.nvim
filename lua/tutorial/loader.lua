-- tutorial.loader
-- Loading definitions from files — the sharing story. Two formats, one
-- registry:
--
--   <name>.lua             full power: returns a definition table; hooks,
--                          predicates, steps-as-function all welcome
--   <name>.tutorial.json   declarative-only data, decoded with vim.json and
--                          purity-checked: no functions can hide inside, so
--                          files from anywhere (teammates, docs, machines)
--                          are safe to load. The portable format for shared
--                          learning resources.
--
-- The JSON shape mirrors the Lua schema minus everything executable:
-- completion specs are strings only (`{ context = fn }` is impossible),
-- input steps validate through `pattern` instead of function validators, and
-- cond/enter/complete/setup/teardown do not exist.

local validate = require("tutorial.validate")

local M = {}

local function fail(msg)
  error("[tutorial.nvim] " .. msg, 0)
end

local function is_json(path)
  return path:sub(-5) == ".json"
end

-- Decode a JSON definition. Purity-checked even though vim.json cannot
-- produce functions — the guard is the contract, not the codec.
function M.from_json(text)
  local ok, def = pcall(vim.json.decode, text)
  if not ok then
    fail("invalid JSON: " .. tostring(def))
  end
  if type(def) ~= "table" then
    fail("a JSON tutorial must decode to an object")
  end
  local pure_ok, pure_err = pcall(validate.assert_pure, def, "definition")
  if not pure_ok then
    fail(pure_err)
  end
  local errors = validate.definition(def)
  if #errors > 0 then
    fail(errors[1])
  end
  return def
end

-- Load a definition file (.lua or .tutorial.json) and register it. Returns
-- the definition.
function M.load_file(path)
  path = vim.fn.expand(path)
  if vim.fn.filereadable(path) ~= 1 then
    fail("no readable tutorial file at " .. path)
  end
  local def
  if is_json(path) then
    local text = table.concat(vim.fn.readfile(path), "\n")
    def = M.from_json(text)
  elseif path:sub(-4) == ".lua" then
    local chunk, err = loadfile(path)
    if not chunk then
      fail(("cannot load %s: %s"):format(path, tostring(err)))
    end
    local ok, result = pcall(chunk)
    if not ok then
      fail(("error running %s: %s"):format(path, tostring(result)))
    end
    def = result
  else
    fail("unsupported tutorial format (want .lua or .tutorial.json): " .. path)
  end
  return require("tutorial.registry").register(def)
end

-- Write a commented starter file next to the user and tell them where it
-- went (:Tutorial new <id>). Lua stays the authoring surface of choice; the
-- scaffold shows the shape and points at the docs.
function M.scaffold(id, target_dir)
  id = id and id ~= "" and id or nil
  if not id then
    fail("an id is required: :Tutorial new <id>")
  end
  require("tutorial.validate").assert_pure({}) -- keep the guard warm in tests
  local dir = target_dir or vim.fn.getcwd()
  local path = dir .. "/" .. id .. ".tutorial.lua"
  if vim.fn.filereadable(path) == 1 then
    fail("refusing to overwrite existing file: " .. path)
  end
  vim.fn.writefile({
    "-- Tutorial scaffold created by :Tutorial new " .. id,
    "-- Register it from your config:",
    "--   require(\"tutorial\").load_file(\"" .. path .. "\")",
    "-- Full reference: :h tutorial-authoring",
    "",
    "return {",
    "  id = \"" .. id .. "\",",
    "  title = \"" .. id .. "\",",
    "  summary = \"One line for the :Tutorial menu\",",
    "  tags = { \"getting-started\" },",
    "  steps = {",
    "    {",
    "      id = \"first\",",
    "      title = \"Do the thing\",",
    "      body = {",
    "        \"One idea per step. Press {key:d} to complete this one.\",",
    "      },",
    "      hint = { \"Ladders reveal one nudge at a time.\", \"This is rung two.\" },",
    "    },",
    "    {",
    "      id = \"second\",",
    "      title = \"Prove it happened\",",
    "      body = { \"Run :echo hello and this step checks itself off.\" },",
    "      completion = { \"on_command:echo\" },",
    "    },",
    "  },",
    "}",
  }, path)
  return path
end

return M
