-- tutorial.nvim entrypoint: define :Tutorial and register the built-in tours
-- when the plugin loads.
require("tutorial").setup()
require("tutorial").register(require("tutorial.tutorials.hello").def)
require("tutorial").register(require("tutorial.tutorials.authoring").def)
