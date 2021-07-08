{ pkgs, lib, sourceOverrides, utils, floxPathDepth, trace }:
let
  getChannelSource = pkgs.callPackage ./getSource.nix {
    inherit sourceOverrides trace;
  };
in
importingChannel:
{ channels
, ownChannel
, file
, scope
, ownScope
, trace
}: {
  inherit getChannelSource;
  getSource = getChannelSource ownChannel;
  getBuilderSource = lib.warn
    ("meta.getBuilderSource as used by channel ${ownChannel} is deprecated,"
      + " use `meta.getChannelSource meta.importingChannel` instead")
    (getChannelSource importingChannel);
  inherit importingChannel ownChannel;

  withVerbosity = throw "meta.withVerbosity was removed, use `meta.trace <subsystem> <verbosity> <message> <value>` instead";
  inherit trace channels;

  mapDirectory = dir: trace.withContext "mapDirectory" (baseNameOf dir) (trace:
    { call ? path: utils.callPackageWith trace scope path }:
    lib.mapAttrs (name: value: call value.path)
    (utils.dirToAttrs trace dir));

  importNix =
    { channel ? importingChannel, project, path, ... }@args: trace.withContext "importNix" "" (trace:
    let
      source = getChannelSource channel project args;
      fullPath = source.src + "/${path}";
      fullPathChecked = if builtins.pathExists fullPath then
        fullPath
      else
        throw
        "`meta.importNix` in ${file}: File ${path} doesn't exist in source for project ${project} in channel ${importingChannel}";
    in {
      # flox edit should edit the path specified here
      _floxPath = fullPath;
      # If we're evaluating for a _floxPath, only let the result of an
      # importNix call influence the _floxPath with a _floxPathDepth
      # greater or equal to 2
      # Note that technically we could pass a nested importNix into the
      # scope which increases the depth by one more, though this
      # doesn't seem to be very beneficial in most cases
    } // lib.optionalAttrs (floxPathDepth >= 2)
      (utils.callPackageWith trace ownScope fullPathChecked));
}
