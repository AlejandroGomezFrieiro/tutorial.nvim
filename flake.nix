{
  description = "tutorial.nvim: a generic interactive walkthrough engine for Neovim plugins.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = inputs @ {self, nixpkgs, ...}: let
    forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
    version = "0.1.0";
  in {
    # The plugin as a Neovim-loadable package (runtimepath source):
    # lazy.nvim:  { dir = tutorial-nvim }
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in rec {
      default = pkgs.runCommand "tutorial-nvim-${version}" {} ''
        mkdir -p $out
        cp -r ${./plugin} $out/plugin
        cp -r ${./lua} $out/lua
        cp -r ${./doc} $out/doc
      '';
    });

    # `nix flake check` runs every derivation here; a non-zero exit fails it.
    checks = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      # Minimal repo source so tests/lint get the exact lua, plugin, tests dirs
      # on the runtimepath without dragging in result*/ or practice files.
      # .stylua.toml must ride along: stylua resolves it during --check.
      src = pkgs.runCommand "tutorial-src" {} ''
        mkdir -p $out
        cp -r ${./lua} $out/lua
        cp -r ${./plugin} $out/plugin
        cp -r ${./tests} $out/tests
        cp ${./.stylua.toml} $out/.stylua.toml
      '';
    in rec {
      test = pkgs.stdenv.mkDerivation {
        name = "tutorial-tests";
        inherit src;
        nativeBuildInputs = [ pkgs.neovim ];
        buildPhase = ''
          cd $src
          export HOME="$TMPDIR"
          nvim --headless -u NONE -l tests/tutorial_spec.lua
        '';
        installPhase = ''
          mkdir -p $out
          touch $out/done
        '';
      };

      lint = pkgs.stdenv.mkDerivation {
        name = "tutorial-lint";
        inherit src;
        nativeBuildInputs = [ pkgs.stylua ];
        buildPhase = ''
          cd $src
          stylua --check lua/ plugin/ tests/
        '';
        installPhase = ''
          mkdir -p $out
          touch $out/done
        '';
      };
    });

    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        packages = [
          pkgs.neovim
          # Lint/format for CI parity.
          pkgs.stylua
          pkgs.luajitPackages.luacheck
        ];
      };
    });
  };
}
