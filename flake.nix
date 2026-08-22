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
