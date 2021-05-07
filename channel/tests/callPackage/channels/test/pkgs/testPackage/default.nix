{ callPackage }: {
  foo = callPackage ./foo.nix { };
  bar = callPackage ./bar.nix { };
}
