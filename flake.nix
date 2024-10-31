# This flake is adopted from: https://github.com/cdepillabout/example-haskell-nix-flake/blob/8c5d1de69f215e43fa224ea6ef9bf4e77de50630/flake.nix
# Some discussions can be found here: https://discourse.nixos.org/t/trying-to-get-nix-flakes-haskell-hls-vscode-to-work-but-nothing-works-properly/26805/8

# Another useful source of flakes for Haskell projects is: https://nixos.asia/en/nixify-haskell-nixpkgs

{
  description = "Flake for Artem's blog";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, flake-utils, nixpkgs }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          config = {};

          overlays = [
            (final: prev: {
              # Local Haskell packages (hopefully) with all the dependendcies
              # needed to build this.
              myHaskellPackages = final.haskellPackages.override {
                overrides = hfinal: hprev: {
                  artem-blog =
                    hfinal.callCabal2nix "artem-blog" ./. {};
                };
              };

              # This is just a convenient shortcut to our package from the
              # top-level of Nixpkgs.  We're also applying the
              # justStaticExecutables function to our package in order to
              # reduce the size of the output derivation.
              artem-blog =
                final.haskell.lib.compose.justStaticExecutables
                  final.myHaskellPackages.artem-blog;

              # A Haskell development shell for our package that includes
              # things like cabal and HLS.
              myDevShell = final.myHaskellPackages.shellFor {
                packages = p: [ p.artem-blog ];

                nativeBuildInputs = [
                  final.imagemagick
                  final.ghostscript
                  final.cabal-install
                  final.haskellPackages.haskell-language-server
                ];
              };
            })
          ];

          # Our full Nixpkgs with the above overlay applied.
          pkgs = import nixpkgs { inherit config overlays system; };
        in
        {
          packages.default = pkgs.artem-blog;
          devShells.default = pkgs.myDevShell;
        }
      );
}
