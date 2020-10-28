{ lib }: {

  # TODO: Also implement the prefix-less lookup
  lookupNixPath = path:
    let
      entry = lib.findFirst (e: lib.hasPrefix e.prefix path)
        (throw "No entry matching ${toString path} found in NIX_PATH") builtins.nixPath;
      suffix = lib.removePrefix entry.prefix path;
    in entry.path + suffix;
}
