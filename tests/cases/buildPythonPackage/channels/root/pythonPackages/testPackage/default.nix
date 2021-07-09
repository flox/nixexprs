{ flox }:
flox.pythonPackages.buildPythonPackage {
  project = "testPackage";
  src = ./src;
  version = "1.0";
}
