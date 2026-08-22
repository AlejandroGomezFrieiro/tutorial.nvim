-- luacheck config for tutorial.nvim
std = "luajit"
globals = { "vim" }
max_line_length = 100

exclude_files = {}

-- Project-wide relaxations:
--   431 shadowing upvalue — repeated pcall(ok, ...) locals
--   213 value assigned but unused — deliberate reassignments before use
--   212 unused argument — shared handler signatures
ignore = { "431", "213", "212", "311" }

files["tests/"] = {
  -- Tests intentionally monkey-patch globals and reuse short loop names.
  ignore = { "122", "shadowing", "211", "221", "231" },
}
