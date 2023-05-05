# default.nix
with import <nixpkgs> {};
stdenv.mkDerivation rec {
    name = "artem-blog-env";
    buildInputs = [ 
        #icu67.dev
        #icu.dev
        #icu
        zlib
        zlib.dev
        #cabal-install
        #haskell.compiler.ghc8104
        #haskell.compiler.ghc8107

        #haskellPackages.alex
        #haskellPackages.happy
        #haskellPackages.text-icu

        pkgconfig
        # To create thumbnails for pdfs.
        imagemagick

        #stack
      ];

    LD_LIBRARY_PATH = lib.makeLibraryPath buildInputs;
}
