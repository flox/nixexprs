{ flox }:
flox.importNix {
  project = "testPackage";
  src = ./src;
  path = "flox.nix";
}
