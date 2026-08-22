-- tutorial.ui.done
-- Completion screen shown when the last step of a tutorial checks off.

local ui = require("tutorial.ui")

local M = {}

function M.open(def)
  local entries = {
    { text = "" },
    { text = "  ✓  TUTORIAL COMPLETE", hl = "TutorialDone" },
    { text = "" },
    {
      segments = {
        { text = "  " },
        { text = def.title, hl = "TutorialKey" },
        { text = " — all steps done." },
      },
    },
    { text = "" },
    { text = "  Progress stays saved; reset from the menu to replay.", hl = "TutorialMuted" },
    { text = "" },
    ui.footer("[m]enu q(close)"),
  }

  local buf = ui.scratch("done", entries)
  ui.show(buf)
  vim.keymap.set("n", "m", function()
    require("tutorial.ui.menu").open()
  end, { buffer = buf, silent = true })
  vim.keymap.set("n", "q", function()
    ui.close_all()
  end, { buffer = buf, silent = true })
end

return M
