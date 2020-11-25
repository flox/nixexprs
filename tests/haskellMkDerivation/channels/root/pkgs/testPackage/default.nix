{ flox }:
flox.haskellPackages.mkDerivation {
  project = "testPackage";
  src = ./src;
}
