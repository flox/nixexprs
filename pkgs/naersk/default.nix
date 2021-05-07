{ callPackage, meta }: {
  buildRustPackage = callPackage ./buildRustPackage.nix { };
}
