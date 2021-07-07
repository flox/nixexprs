{ lib
, spec
, pname
, perChannelPackages
, createMeta
, ownChannel
, trace
, floxPathDepth
, originalSet
, overlaidSet
, baseScope
, channels
}:
let

  superPackage =
    if spec.extends == null then
      throw "${pname} is accessed in ${spec.exprPath}, but is not defined because nixpkgs has no ${pname} attribute"
    else if spec.extends == "nixpkgs" then
      if spec.deep then originalSet.${pname} else overlaidSet.${pname}
    else if ! perChannelPackages ? ${spec.extends} then
      throw "extends channel ${spec.extends} doesn't exist"
    else if ! perChannelPackages.${spec.extends} ? ${pname} then
      throw "extends package ${pname} doesn't exist in channel ${spec.extends}"
    else perChannelPackages.${spec.extends}.${pname};

  # TODO: Probably more efficient to directly inspect function arguments and fill these entries out.
  # A callPackage abstraction that allows specifying multiple attribute sets might be nice
  createScope = isOwn:
    baseScope // lib.optionalAttrs isOwn {
      ${pname} = superPackage;
    } // {
      # These attributes are reserved
      inherit channels;
      meta = createMeta {
        inherit trace ownChannel channels scope ownScope;
        exprPath = spec.exprPath;
      };
      flox = channels.flox;
      callPackage = lib.callPackageWith scope;
    };

  ownScope = createScope true;
  scope = createScope false;

  ownOutput = {
    # Allows getting back to the file that was used with e.g. `nix-instantiate --eval -A foo._floxPath`
    # Note that we let the callPackage result override this because builders
    # like flox.importNix are able to provide a more accurate file location
    _floxPath = spec.exprPath;
    # If we're evaluating for a _floxPath, only let the result of an
    # package call influence the _floxPath with a _floxPathDepth
    # greater or equal to 1
  } // lib.optionalAttrs (floxPathDepth >= 1)
    (lib.callPackageWith ownScope spec.exprPath { });

in ownOutput
