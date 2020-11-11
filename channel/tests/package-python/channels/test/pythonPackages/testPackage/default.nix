{ python, pythonPackages }: {
  name = assert python.name == pythonPackages.python.name; python.name;
}
