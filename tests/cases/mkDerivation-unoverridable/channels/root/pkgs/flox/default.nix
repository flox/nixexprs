{ flox, hello }:
flox.mkDerivation {
  project = "flox";
  src = hello.src;
  version = "1.0";
}
