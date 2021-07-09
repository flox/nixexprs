let
  value = import <test> { };
  levels = [
    value.haskell.recurseForDerivations
    value.haskell.packages.recurseForDerivations
    value.haskell.packages.ghc884.recurseForDerivations
  ];
in levels
