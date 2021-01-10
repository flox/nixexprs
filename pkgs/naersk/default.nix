{ callPackage, meta }:
{
  buildRustPackage = callPackage ./buildRustPackage.nix {
    inherit meta;
  };
}
