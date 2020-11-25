{ flox }:
flox.pythonPackages.buildPythonApplication {
  project = "testPackage";
  src = ./src;
}
