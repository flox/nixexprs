{ flox }:
flox.pythonPackages.buildPythonPackage {
  project = "flox";
  src = ./src;
  version = "1.0";
}
