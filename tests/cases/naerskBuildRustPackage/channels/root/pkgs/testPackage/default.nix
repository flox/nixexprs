{ flox }:
flox.naersk.buildRustPackage {
  project = "testPackage";
  src = ./src;
  version = "1.0";
}
