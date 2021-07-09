{ flox }:
flox.haskellPackages.mkDerivation {
  project = "testPackage";
  src = ./src;
  version = "1.0";
}
