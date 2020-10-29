{ pythonPackages, flox }:

flox.builders.buildPythonApplication {
  project = "example-python";
}
