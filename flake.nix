{
  description = "moore-mud — a MUD engine on coalgebraic Moore/Mealy machines";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      ghcVersion = "98";
      compiler = "ghc${ghcVersion}";
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        evalPkgs = import nixpkgs { system = "x86_64-linux"; };

        mkHsPkgs =
          compiler:
          evalPkgs.haskell.packages.${compiler}.override {
            overrides = hfinal: hprev: {
              machines-coalgebras =
                hfinal.callCabal2nix "machines-coalgebras"
                  ("${
                    pkgs.fetchFromGitHub {
                      owner = "cofree-coffee";
                      repo = "cofree-bot";
                      rev = "e2693672507cc1278ccee7f9bb2037a44f7e9ea6";
                      sha256 = "sha256-0baP8yvHNSGxqjMNmXthLhtjoFhJ3SP33Ft4CI2vTeg=";
                    }
                  }/machines-coalgebras")
                  { };
              monoidal-functors =
                hfinal.callCabal2nix "monoidal-functors"
                  (pkgs.fetchFromGitHub {
                    owner = "solomon-b";
                    repo = "monoidal-functors";
                    rev = "e16e1bfbcfc19c8aadfc7bcf65c9e7de59d63b83";
                    sha256 = "sha256-HfIMuU9yBp0JtN/ONOFku1wItbGLJl09fhaFzyiNVMg=";
                  })
                  { };
              bidir-serializers = hfinal.callCabal2nix "bidir-serializers" ./bidir-serializers/. { };
              machines-frp = hfinal.callCabal2nix "machines-frp" ./machines-frp/. { };
              moore-mud = hfinal.callCabal2nix "moore-mud" ./moore-mud/. { };
            };
          };

        hsPkgs = mkHsPkgs compiler;
      in
      {
        devShells.default = hsPkgs.shellFor {
          packages = p: [
            p.bidir-serializers
            p.machines-frp
            p.moore-mud
          ];
          buildInputs = [
            pkgs.cabal-install
            pkgs.haskell.compiler.${compiler}
            pkgs.haskell.packages.${compiler}.haskell-language-server
            pkgs.ormolu
            pkgs.hlint
            pkgs.ghcid
            pkgs.just
          ];
        };

        packages = {
          bidir-serializers = hsPkgs.bidir-serializers;
          machines-frp = hsPkgs.machines-frp;
          moore-mud = hsPkgs.moore-mud;
          default = hsPkgs.moore-mud;
        };

        apps = {
          default = flake-utils.lib.mkApp {
            drv = hsPkgs.moore-mud;
            name = "moore-mud-server";
          };
          repl = flake-utils.lib.mkApp {
            drv = hsPkgs.moore-mud;
            name = "moore-mud-repl";
          };
          nav-repl = flake-utils.lib.mkApp {
            drv = hsPkgs.moore-mud;
            name = "moore-mud-nav-repl";
          };
        };
      }
    );
}
