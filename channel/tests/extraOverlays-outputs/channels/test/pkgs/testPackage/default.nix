{ stdenv }: stdenv.mkDerivation {
  name = "test";
  passthru.result = "result";
}
