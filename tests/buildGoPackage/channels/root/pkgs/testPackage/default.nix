{ flox }:
flox.buildGoPackage {
  project = "testPackage";
  src = ./src;
  goPackagePath = "hello";
}
