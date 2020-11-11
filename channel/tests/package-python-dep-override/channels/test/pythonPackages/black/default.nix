{ black, toml, pythonPackages }: {
  result = {
    blackName = black.name;
    tomlResult = toml.result;
    blackName2 = pythonPackages.black.name;
    tomlResult2 = pythonPackages.toml.result;
  };
}
