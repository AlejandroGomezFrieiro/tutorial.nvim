# AGENTS.md

Neovim-only Lua plugin, zero runtime dependencies. Public API is `require("tutorial")` (`register`, `start`, `active`, `quit`, `status`, `setup`) in `lua/tutorial/init.lua`. Internals: `registry`, `engine`, `state`, `checks`, `config`, and `ui/*`.

## Commands

- The whole-gate command is `nix flake check`: it builds every derivation in the `checks` output of `flake.nix` and fails on any non-zero exit. Use `nix flake check --no-build` (evaluate only) or `nix build .#checks.<system>.test` for a fast individual check.
- Test (whole suite is one file, no per-test granularity): `nvim --headless -u NONE -l tests/tutorial_spec.lua`; exit is `os.exit(failed == 0 and 0 or 1)`.
- Lint: `stylua --check lua/ plugin/ tests/` — but it MUST run with `.stylua.toml` present, so run it via `nix develop -c stylua --check ...` or `nix build .#checks.<system>.lint` (otherwise stylua falls back to default config).
- Lua style: `.stylua.toml` (Lua52 syntax, double quotes, 100 col). luacheck config is `.luacheckrc` but is NOT in CI.
- Dev tools come from the Nix devShell, not your shell: `nix develop` (provides `neovim`, `stylua`, `luacheck`).

CI runs `nix flake check` (tests + stylua) on a pinned nixpkgs Neovim from `flake.lock`.

## Architecture notes

- Entrypoint is `plugin/tutorial.lua`: it calls `require("tutorial").setup()` and registers the two built-in tours `hello` and `authoring`. The plugin is lazy-loaded via `cmd = "Tutorial"`, so `setup()` also defines the `:Tutorial` user command.
- Test hooks are exposed as unexported fields on the module (`tutorial._registry`, `_engine`, `_state`, `_checks`, `_config`). They are how tests reset registry/state; keep them.
- Progress is write-once JSON under `stdpath("data")/tutorial/<id>.json`; only `:Tutorial reset [id]` un-checks a step. Tests must isolate it with `state._set_dir(vim.fn.tempname() ...)`.
- Tutorials must NOT attach their own autocmds. All completion events flow through the single hub in `engine.lua` (User / CmdlineLeave / BufEnter / BufWritePost / CursorHold). `advancing` in `engine.lua` guards re-entrancy during render — complete steps off the render tick.
- Completion specs live in `checks.lua`: edge specs (`on_command:`, `on_event:`, `on_buffer:`) fire on their event; state specs (`on_file_exists:`, `on_file_contains:`, `{ context = fn }`) are polled. Predicates are wrapped in `pcall` — an erroring check is false, not fatal.
- Default `layout` pins a side panel (split) and never moves focus; `layout = "card"` owns the full window. Re-running `:Tutorial` while active toggles the panel / reopens the card.

## Conventions

- Authoring schema and completion spec semantics are specified in `docs/authoring.md`; `docs/design.md` explains the engine's reasoning. `doc/tutorial.txt` is the generated-style Neovim help file and must stay consistent if either changes.
- Registry rejects definitions without an `id` and steps with duplicate ids; re-registering an id replaces the definition in place (keeps menu position).
- `.gitignore` ignores `result*` (Nix build output) and `my-tutorial.lua` (a local practice file).
