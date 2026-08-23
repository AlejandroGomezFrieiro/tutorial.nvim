-- tutorial.ui.done
-- Completion screen shown when the last step of a tutorial checks off.
-- Content is the shared summary (ui.done_lines) with its own footer keys.

local ui = require("tutorial.ui")

local M = {}

function M.open(def)
  local buf = ui.scratch("done", ui.done_lines(def, "[m]enu q(close)"))
  ui.show(buf)
  vim.keymap.set("n", "m", function()
    require("tutorial.ui.menu").open()
  end, { buffer = buf, silent = true })
  vim.keymap.set("n", "q", function()
    ui.close_all()
  end, { buffer = buf, silent = true })
end

return M
