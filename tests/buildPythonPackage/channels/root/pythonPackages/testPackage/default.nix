{ flox }:
flox.pythonPackages.buildPythonPackage {
  project = "testPackage";
  src = ./src;
}
