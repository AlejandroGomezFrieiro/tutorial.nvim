-- tutorial.tutorials.authoring
-- The second built-in tour: write a real tutorial from scratch, register it,
-- and take it for a spin — while the engine watches and checks you off.

local M = {}

M.def = {
  id = "authoring",
  title = "Write your first tutorial",
  summary = "Build a working tutorial from scratch, register it, and run it.",
  steps = {
    {
      id = "anatomy",
      title = "The anatomy of a tutorial",
      body = {
        "A tutorial is a table. That is genuinely the whole data model:",
        "",
        "    {",
        "      id = \"...\",        -- unique name for :Tutorial <id>",
        "      title = \"...\",     -- shown in menus and cards",
        "      steps = { ... },   -- ordered; each step is also a table",
        "    }",
        "",
        "Steps carry a title, body lines, an optional hint, and completion",
        "specs — command runs, User events, buffer opens, file state, or any",
        "Lua predicate. Any spec matching completes the step; {key:d} always",
        "works too.",
        "",
        "Press {key:d} when this has sunk in.",
      },
      hint = ":h tutorial-authoring has the full reference.",
    },
    {
      id = "write",
      title = "Write one to disk",
      body = {
        "Create my-tutorial.lua in your current directory (:edit works) with",
        "this content, then :write it:",
        "",
        "    return {",
        "      id = \"my-first\",",
        "      title = \"My first tutorial\",",
        "      steps = {",
        "        {",
        "          id = \"hello\",",
        "          title = \"Say hi\",",
        "          body = { \"You are inside your own tutorial.\" },",
        "        },",
        "        {",
        "          id = \"act\",",
        "          title = \"Do a thing\",",
        "          body = { \"Run :echo well hello there\" },",
        "          completion = { \"on_command:echo\" },",
        "        },",
        "      },",
        "    }",
        "",
        "Saving it completes this step — the engine noticed the file.",
      },
      hint = "The file only needs to return the table; nothing else loads it yet.",
      completion = { "on_file_exists:my-tutorial.lua" },
    },
    {
      id = "register",
      title = "Register it with the engine",
      body = {
        "Plugins register tutorials at load time. For a loose file on disk,",
        "register it by hand right now:",
        "",
        "    :lua require(\"tutorial\").register(dofile(\"my-tutorial.lua\"))",
        "",
        "This step completes the moment a tutorial with id \"my-first\" exists",
        "in the registry — keep that id, or press {key:d} if you named it",
        "something else.",
      },
      hint = "dofile runs relative to your cwd, same place :edit looked.",
      completion = {
        {
          context = function()
            local registry = require("tutorial.registry")
            return registry.get("my-first") ~= nil
          end,
        },
      },
    },
    {
      id = "spin",
      title = "Take yours for a spin",
      body = {
        "It is a real tutorial now. Start it:",
        "",
        "    :Tutorial my-first",
        "",
        "Finish its two steps ({key:d}, then the echo), press {key:q} to pause",
        "it, and come back here. Your progress on both tours is saved side by",
        "side.",
      },
      hint = "Starting another tutorial pauses this one; resume from the menu.",
    },
  },
}

return M
