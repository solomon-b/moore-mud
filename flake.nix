{
  description = "machines-frp — FRP on coalgebraic Moore/Mealy machines";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      hsPkgs = pkgs.haskell.packages.ghc98;
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        nativeBuildInputs = [
          hsPkgs.ghc
          hsPkgs.cabal-install
          hsPkgs.haskell-language-server
          pkgs.ormolu
          pkgs.hlint
          pkgs.ghcid
          pkgs.just
        ];
      };
    };
}
