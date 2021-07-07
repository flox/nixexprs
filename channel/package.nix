{ lib
, pkgs
, myPkgs
, versionInfo
, spec
, pname
, called
, setName
, version
, perImportingChannel
, ownChannel
, packageSets
, createMeta
, trace
, importingChannel
, name
, channelPackageSpecs
, _floxPathDepth
}:
let

  deepAnchor = lib.getAttrFromPath versionInfo.canonicalPath pkgs;
  shallowAnchor = lib.getAttrFromPath versionInfo.canonicalPath myPkgs;

  superPackage =
    if spec.extends == null then
      throw "${pname} is accessed in ${spec.exprPath}, but is not defined because nixpkgs has no ${pname} attribute"
    else if spec.extends == "nixpkgs" then
      if spec.deep then deepAnchor.${pname} else shallowAnchor.${pname}
    else if ! called ? ${spec.extends} then
      throw "extends channel ${spec.extends} doesn't exist"
    else if ! called.${spec.extends}.${setName}.${version} ? ${pname} then
      throw "extends package ${pname} doesn't exist in channel ${spec.extends}"
    else called.${spec.extends}.${setName}.${version}.${pname};

  packageSetScope = lib.getAttrFromPath versionInfo.canonicalPath perImportingChannel.${ownChannel}.baseScope // {
    ${packageSets.${setName}.callScopeAttr} = packageSetScope;
  };

  baseScope' = perImportingChannel.${ownChannel}.baseScope
    // lib.optionalAttrs (packageSets.${setName}.callScopeAttr != null) {
      ${packageSets.${setName}.callScopeAttr} = packageSetScope;
    };

  extraScope = lib.optionalAttrs (packageSets.${setName}.callScopeAttr != null) packageSetScope;

  # TODO: Probably more efficient to directly inspect function arguments and fill these entries out.
  # A callPackage abstraction that allows specifying multiple attribute sets might be nice
  createScope = isOwn:
    let
      channels =
        let
          original = lib.mapAttrs (channel: value:
            let
              x = lib.mapAttrs (pname:
                lib.warn "Accessing channel.${name}.${pname} from ${spec.exprPath}. This is discouraged as it circumvents the conflict resolution mechanism. Add ${pname} to the argument list directly instead."
              ) perImportingChannel.${ownChannel}.outputs.${channel};
            in x // {
              ${packageSets.${setName}.callScopeAttr} = lib.getAttrFromPath versionInfo.canonicalPath x;
            }
          ) channelPackageSpecs;
        in original // lib.mapAttrs' (name: lib.nameValuePair (lib.toLower name)) original;

      result =
        baseScope' // extraScope // lib.optionalAttrs isOwn {
          ${pname} = superPackage;
        } // {
          # These attributes are reserved
          inherit channels;
          meta = createMeta {
            inherit trace channels ownChannel importingChannel scope ownScope;
            exprPath = spec.exprPath;
          };
          flox = channels.flox;
          callPackage = lib.callPackageWith scope;
        };
    in result;

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
  } // lib.optionalAttrs (_floxPathDepth >= 1)
    (lib.callPackageWith ownScope spec.exprPath { });

in ownOutput
