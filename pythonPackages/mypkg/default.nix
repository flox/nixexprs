{ stdenv, pythonPackages, flox }:
flox.builders.mkDerivation {
  project = "mypkg";
}
