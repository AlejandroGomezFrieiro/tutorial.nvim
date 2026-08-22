# tutorial.nvim

> Interactive walkthroughs for Neovim plugins

[![CI](https://github.com/AlejandroGomezFrieiro/tutorial.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/AlejandroGomezFrieiro/tutorial.nvim/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Neovim](https://img.shields.io/badge/neovim-0.9%2B-44cc11?logo=neovim&logoColor=white)

`tutorial.nvim` is a small tutorial/walkthrough engine that allows users
to take a hands-on approach to familiarizing themselves with a new plugin. Similar
in spirit to [vim_tutor_mode](https://neovim.io/doc/user/pi_tutor/) and
[vimtutor](https://vimschool.netlify.app/introduction/vimtutor/) but
with a general approach to it.

This plugin came as a sort of necessity while developing
[storyteller.nvim](https://github.com/AlejandroGomezFrieiro/storyteller.nvim)
as I realized that a User Guide was always going to be insufficient for
actually teaching newcomers how to use it.

I recommend that, after installing the tutorial, you run `:Tutorial` to
evaluate how helpful the engine is.

## Requirements

- Neovim 0.9+.

## Installation

```lua
{
  "AlejandroGomezFrieiro/tutorial.nvim",
  cmd = "Tutorial",
}
```

## Usage

Two tutorials are used, one demo and one that teaches you how to develop
your own tutorials.

```
:Tutorial              choose a tour from the menu
:Tutorial [id]         start/resume one directly
:Tutorial reset [id]   forget progress (one, or all)
```

While a tutorial runs it stays pinned in a split beside your work; steps
check off without ever moving your cursor. Keys, configuration, and
statusline integration are covered in [docs/running.md](docs/running.md).

## Creating a tutorial

Run `:Tutorial authoring` for the basics, which will teach you how to write a
tutorial called `my-first`

For more information, see [docs](docs/)

## AI disclaimer

`tutorial.nvim` was developed with the aid of AI tools.

## License

MIT
