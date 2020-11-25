{ flox, hello }:
flox.mkDerivation {
  project = "testPackage";
  src = hello.src;
}
