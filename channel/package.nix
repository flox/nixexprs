{ lib
, utils
, floxPath
, floxFile
, importingChannel
, ownChannel
, trace
, floxPathDepth
, baseScope
, channels
, flox
, superScope
, getChannelSource
}:
let

  meta = {
    inherit getChannelSource;
    getSource = getChannelSource ownChannel;
    getBuilderSource = lib.warn
      ("meta.getBuilderSource as used in ${floxFile} is deprecated,"
        + " use `meta.getChannelSource meta.importingChannel` instead")
      (getChannelSource importingChannel);
    inherit importingChannel ownChannel;

    withVerbosity = throw "meta.withVerbosity as used in ${floxFile} was removed, use `meta.trace <subsystem> <verbosity> <message> <value>` instead";
    inherit trace channels;

    mapDirectory = dir: trace.withContext "mapDirectory" (baseNameOf dir) (trace:
      { call ? path: utils.callPackageWith trace scope path }:
      lib.mapAttrs (name: value: call value.path)
      (utils.dirToAttrs trace dir) // {
        recurseForDerivations = true;
      });

    importNix =
      { channel ? importingChannel, project, path, ... }@args: trace.withContext "importNix" "" (trace:
      let
        source = getChannelSource channel project args;
        fullPath = source.src + "/${path}";
        fullPathChecked = if builtins.pathExists fullPath then
          fullPath
        else
          throw
          "`meta.importNix` in ${floxFile}: File ${path} doesn't exist in source for project ${project} in channel ${importingChannel}";
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
  };

  # TODO: Probably more efficient to directly inspect function arguments and fill these entries out.
  # A callPackage abstraction that allows specifying multiple attribute sets might be nice
  createScope = isOwn:
    baseScope // lib.optionalAttrs isOwn superScope // {
      # These attributes are reserved
      inherit channels flox meta;
      callPackage = lib.callPackageWith scope;
    };

  ownScope = createScope true;
  scope = createScope false;

  ownOutput = {
    # Allows getting back to the file that was used with e.g. `nix-instantiate --eval -A foo._floxPath`
    # Note that we let the callPackage result override this because builders
    # like flox.importNix are able to provide a more accurate file location
    _floxPath = floxPath;
    # If we're evaluating for a _floxPath, only let the result of an
    # package call influence the _floxPath with a _floxPathDepth
    # greater or equal to 1
  } // lib.optionalAttrs (floxPathDepth >= 1)
    (utils.callPackageWith trace ownScope floxFile);

in ownOutput
