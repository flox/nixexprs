{ flox, hello }:
flox.mkDerivation {
  project = "testPackage";
  src = hello.src;
  version = "1.0";
}
