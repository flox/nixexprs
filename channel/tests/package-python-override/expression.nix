let
  channel = import <test> {};
in {
  blackName = channel.python3Packages.black.result;
  tomlName = channel.python3Packages.toml.result;
}
