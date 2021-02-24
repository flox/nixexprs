{ flox }:
flox.pythonPackages.buildPythonApplication {
  project = "testPackage";
  src = ./src;
  version = "1.0";
}
