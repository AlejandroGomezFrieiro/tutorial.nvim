{
  description = "tutorial.nvim: a generic interactive walkthrough engine for Neovim plugins.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    # The demo build rides on the author's own Neovim configuration — the
    # local checkout next to this repo. Nix cannot take a `path:../…` input
    # from a git-tree flake (the source is copied into the store, where `..`
    # dangles), so the sibling repo is pinned by its local git URL instead.
    nixvim.url = "github:nix-community/nixvim";
    nixvim.inputs.nixpkgs.follows = "nixpkgs";
    nixvim_config.url = "github:AlejandroGomezFrieiro/nixvim_config";
    nixvim_config.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixvim,
    nixvim_config,
    ...
  }: let
    forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
    version = "0.1.0";

    # Demo Neovim: the full personal config from ../nixvim_config as the
    # default configuration, with this plugin dropped onto the runtimepath.
    # Only exposed as an app/devShell — `nix flake check` builds every
    # package, and this one is far too heavy for CI.
    demoNvim = system:
      nixvim.legacyPackages.${system}.makeNixvimWithModule {
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg:
            builtins.elem (pkg.pname or pkg.name) ["blink-cmp-spell"];
        };
        module = {
          imports = [nixvim_config.nixosModules.default];
          # Classic command line for the recording; noice/image float over
          # the walkthrough panel and hide what the demo is showing.
          nixvim-config.ui.noice.enable = false;
          nixvim-config.ui.image.enable = false;
          # Wider walkthrough panel so step titles and key hints don't wrap
          # mid-word on camera (plugin/tutorial.lua re-setup()s bare, which
          # is a no-op merge and leaves this standing).
          extraConfigLua = ''
            require("tutorial").setup({panel_width = 54})
          '';
          extraPlugins = [self.packages.${system}.default];
        };
      };
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

    # `nix run .#demo` opens Neovim running the author's config with
    # tutorial.nvim loaded.
    apps = forAllSystems (system: rec {
      demo = {
        type = "app";
        program = "${demoNvim system}/bin/nvim";
      };
      default = demo;
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

      # Re-record docs/demo.gif: `nix develop .#demo -c vhs demo.tape`
      demo = pkgs.mkShell {
        packages = [
          (demoNvim system)
          pkgs.vhs
          pkgs.tmux
          pkgs.ffmpeg
        ];
      };
    });
  };
}
