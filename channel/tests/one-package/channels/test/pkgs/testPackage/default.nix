{ stdenv, hello }: stdenv.mkDerivation {
  name = "testPackage";
  buildInputs = [ hello ];
}
