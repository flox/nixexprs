{ mkDerivation, meta }:
meta.importNix {
  project = "testPackage";
  src = ./src;
  path = "flox.nix";
}
