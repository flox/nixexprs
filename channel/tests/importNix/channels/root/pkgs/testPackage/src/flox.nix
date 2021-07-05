{ flox, hello }:
(builtins.trace (flox ? mkDerivation) flox).mkDerivation {
  project = "testPackage";
  src = hello.src;
  version = "1.0";
}
