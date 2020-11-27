{ flox }:
flox.buildGoPackage {
  project = "testPackage";
  src = ./src;
  version = "1.0";
  goPackagePath = "hello";
}
