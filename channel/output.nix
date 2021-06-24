# Returns the auto-generated output of a channel
# TODO: Add debug logs
{ pkgs, outputFun, channelArgs, trace, sourceOverrides, packageSets, utils }:
let
  inherit (pkgs) lib;

  # TODO: Error if conflicting paths. Maybe on the package-sets.nix side already though
  mergeSets = lib.foldl' lib.recursiveUpdate { };

in importPath: parentOverlays: parentArgs: myArgs: (trace.setContext "importPath" importPath).withContext "channel" myArgs.name (trace:
let

  appVersionTrees = lib.mapAttrs (name: value:
    utils.versionTreeLib.library.setDefault "" (myArgs.defaultLibraryVersions.${name} or "") value.versionTree
  ) packageSets;

  /* Imports all directories and Nix files of the given package directory subpath. Returns
      {
        # For attributes that have { deep = true; } in their package directory (doesn't work for files)
        deep = {
          <name> = <value>;
        };
        # For attributes that don't have { deep = true; }
        shallow = {
          <name> = <value>;
        };
      }
     See dirToAttrs for the fields of <value>
  */
  packageSetFuns = trace: subpath:
    let
      dir = myArgs.topdir + "/${subpath}";

      entries = lib.mapAttrsToList lib.nameValuePair
        (utils.dirToAttrs trace dir);

      parts = lib.mapAttrs (n: v: lib.listToAttrs v)
        (lib.partition (e: e.value.deep) entries);

    in {
      deep = parts.right;
      shallow = parts.wrong;
    };

  toplevel = trace.withContext "" "toplevel" (trace:
    let
      funs = packageSetFuns trace "pkgs";
    in {
      deep = [{
        name = "toplevel";
        deepOverride = a: b: b;
        path = [ ];
        defaultPath = [ ];
        extraScope = null;
        funs = funs.deep;
        libraryVersions = {};
        defaultTypes = {};
      }];
      shallow = [{
        name = "toplevel";
        # TODO: Nest extraScope, funs, path, libraryVersions under createSet attribute, to indicate that it's used by that function
        recurse = true;
        path = [ ];
        extraScope = null;
        funs = funs.shallow;
        libraryVersions = {};
        defaultTypes = {};
      }];
    });

  packageSetOutputs = setName: spec: trace.withContext "package-set" setName (trace:
    let

      funs = packageSetFuns trace spec.callScopeAttr;

      deepOutputs =
        let
          output = el:
            lib.optional (el.valueAttrPath == []) {
              name = setName;
              inherit (el) path;
              defaultPath = [ spec.callScopeAttr ];
              deepOverride = spec.deepOverride;
              extraScope = spec.callScopeAttr;
              funs = funs.deep;
              libraryVersions.${setName} = utils.versionTreeLib.library.queryDefault el.versionPrefix packageSets.${setName}.versionTree;
              defaultTypes.${setName} = "lib";
            };

        in lib.concatMap output spec.attrPaths;

      shallowOutputs = [{
        name = setName;
        recurse = true;
        path = [ spec.callScopeAttr ];
        extraScope = spec.callScopeAttr;
        funs = funs.shallow;
        libraryVersions = {};
        defaultTypes.${setName} = "lib";
      }];

    in {
      deep = deepOutputs;
      shallow = shallowOutputs;
    });

  /* A list of entries describing an output set, each of the form
     {
       name = <name for this output set>;
       path = <attribute path where this set should end up in the channels result>;
       recurse = <bool whether it should be recursed into by hydra>;
       extraScope = <attribute set of additional scope to provide to auto-called packages>;
       channels = <channel attribute set to provide in the scope>;
       deepOverride = <set: overrides: How to deeply override this output with nixpkgs overlays using the given overrides>;
       funs = <result from packageSetFuns, contains all package functions, split into deep/shallow>;
     }

     or if it's an alias definition
   */

  # { deep = [ { ... } ... ]; shallow = [ { ... } ... ]; }
  outputSpecs =
    let
      items = [ toplevel ]
        ++ lib.mapAttrsToList packageSetOutputs packageSets;
    in lib.zipAttrsWith (name: lib.concatLists) items;

  meta = rec {
    getChannelSource =
      pkgs.callPackage ./getSource.nix { inherit sourceOverrides; };
    getSource = getChannelSource ownChannel;
    getBuilderSource = lib.warn
      ("meta.getBuilderSource as used by channel ${myArgs.name} is deprecated,"
        + " use `meta.getChannelSource meta.importingChannel` instead")
      (getChannelSource importingChannel);
    ownChannel = myArgs.name;
    importingChannel = parentArgs.name;
  };

  allPackageSetVersions = lib.mapAttrs (name: value: lib.attrNames value.versions) packageSets;

  /* The outputs of each channel as imported by this channel.

     This calls this very function of this file (outputFun) again, but with this
     channels overlays and arguments passed as parentOverlays/parentArgs. This
     means that there is no caching of channel outputs between different accessors
     of that channel. In turn however this allows deep overrides over the whole
     channel dependency tree.

    { python, perl, haskell, erlang }: {
      pkgs = <pkgs>;
      channels.<channel> = <outputs>;
    };
  */
  versionSetSpecific = utils.memoizeFunctionParameters trace allPackageSetVersions (libraryVersions: trace.withContext "libraryVersions" libraryVersions (trace:
    let

      # Construct a single pkgs for all library versions of a channel
      # Should overlay all canonical package set paths

      # All the overlays that should be applied to the pkgs base set for this
      # channels evaluation (and all the channels it imports)
      myOverlays = let

        #deepSpecTrace = spec:
        #  builtins.trace "[channel ${myArgs.name}] [path ${
        #    lib.concatStringsSep "." spec.path
        #  }] Deeply overriding attributes ${
        #    toString (lib.attrNames spec.funs.deep)
        #  }" spec;

        # Only the output sets that need a deep override
        # We do this so we can avoid having to add an overlay if not necessary
        #deepOutputSpecs = withVerbosity 6 (map deepSpecTrace)
        #  (lib.filter (o: o.funs.deep or { } != { }) outputSpecs);

        deepOverlay = self: super:
          let
            deepOverlaySet = spec:
              utils.attrs.overlaySet super spec.path (superSet:
                trace "overlay" 5 "Creating overriding package set" spec.deepOverride superSet
                (createSet spec superSet));
          in mergeSets (map deepOverlaySet outputSpecs.deep);

        # See https://github.com/flox/floxpkgs/blob/staging/docs/expl/deep-overrides.md#channel-dependencies for why this order seems to be reversed
      in lib.optional (lib.any (x: x.funs != {}) outputSpecs.deep) deepOverlay ++ myArgs.extraOverlays
        ++ parentOverlays;


      myPkgs =
        let
          original = pkgs.appendOverlays myOverlays;

          result = el: {
            path = el.path;
            value = throw "Can't access ${el.path} from nixpkgs. This shouldn't really occur";
          };

          redactingList = lib.concatLists (lib.mapAttrsToList (name: pvalue:
            map result pvalue.attrPaths
            ++ [{
              path = [ pvalue.callScopeAttr ];
              value = lib.getAttrFromPath pvalue.versions.${libraryVersions.${name}} original;
            }]
          ) packageSets);

        in utils.attrs.updateAttrByPaths redactingList original;


      channels =
        let
          cased = lib.mapAttrs (name: args:
            outputFun (importPath ++ [ myArgs.name ]) myOverlays myArgs args libraryVersions
          ) channelArgs;

          lowercased =
            lib.mapAttrs' (name: lib.nameValuePair (lib.toLower name)) cased;
        in cased // lowercased;

      createSet = spec: super: (trace.setContext "package-set" spec.name).withContext "path" spec.path (trace:
        lib.mapAttrs (pname: value: trace.withContext "package" pname (trace:
          let
            defaultedConfig = lib.mapAttrs (name: pvalue:
              let
                config = value.config.packageSets.${name} or {};
                type = config.type or spec.defaultType.${name} or "app";
                version = {
                  app = {
                    app.version = utils.versionTreeLib.library.queryDefault (config.app.version or "") appVersionTrees.${name};
                  };
                  lib = {};
                }.${type} or
                  (throw ''
                    In ${value.path}/config.nix, packageSets.${name}.type is specified to be "${config.type}", which is not a valid value.
                    Select either "app" or "lib"
                  '');
              in version // { inherit type; }
            ) packageSets;

            packageSetVersions = lib.mapAttrs (name: pvalue:
              {
                app = pvalue.app.version;
                lib = spec.libraryVersions.${name} or libraryVersions.${name};
              }.${pvalue.type}
            ) defaultedConfig;

            channels = lib.mapAttrs (channel: channelValue:
              utils.attrs.updateAttrByPaths (redactingList [ "channels" channel "outputs" ]) channelValue.outputs
            ) localVersions.channels;

            localVersions = versionSetSpecific packageSetVersions;

            localMeta = meta // {
              inherit channels;
              trace = trace.setContext "" "user-trace";

              mapDirectory = dir:
                { call ? path: callPackage path { } }:
                lib.mapAttrs (name: value: call value.path)
                (utils.dirToAttrs (trace.setContext "" "mapDirectory") dir);

              importNix =
                { channel ? meta.importingChannel, project, path, ... }@args:
                let
                  source = meta.getChannelSource channel project args;
                  fullPath = source.src + "/${path}";
                  fullPathChecked = if builtins.pathExists fullPath then
                    fullPath
                  else
                    throw
                    "`meta.importNix` in ${value.path}: File ${path} doesn't exist in source for project ${project} in channel ${meta.importingChannel}";
                in {
                  # flox edit should edit the path specified here
                  _floxPath = fullPath;
                } // ownCallPackage fullPathChecked { };
            };

            createScopes = isOwn:
              [
                localVersions.baseScope
                redactingSet
              ]
              ++ lib.optional (spec.extraScope != null) localVersions.baseScope.${spec.extraScope}
              ++ lib.optional isOwn
                {
                  ${pname} = super.${pname} or (throw
                    "${pname} is accessed in ${value.path}, but is not defined because nixpkgs has no ${pname} attribute");
                }
              ++ [{
                meta = localMeta;
                inherit (localMeta) channels;
                flox = localMeta.channels.flox or (throw
                  "Attempted to access flox channel from channel ${myArgs.name}, but no flox channel is present in NIX_PATH");
                inherit callPackage;
              }];

            redact = selfAttr: name: el:
              let
                callScopeAttr = packageSets.${name}.callScopeAttr;
                passthru = lib.getAttrFromPath (selfAttr ++ [ callScopeAttr ] ++ el.valueAttrPath) localVersions;
                stringVersionPrefix = lib.concatStringsSep "." el.versionPrefix;
                genericPath = lib.optional (el.valueAttrPath != [] && spec.extraScope != callScopeAttr) callScopeAttr ++ el.valueAttrPath;

                alternateAppVersions = versionSetSpecific (packageSetVersions // {
                  ${name} = utils.versionTreeLib.core.queryDefault el.versionPrefix appVersionTrees.${name};
                });
                alternate = lib.getAttrFromPath (selfAttr ++ [ callScopeAttr ] ++ el.valueAttrPath) alternateAppVersions;
              in
              if el.versionPrefix == [] then
                trace "redacting" 3 "Allowing access to ${trace.showValue el.path}" passthru
              else if defaultedConfig.${name}.type != "app" then
                throw ''
                  In ${value.path}, the attribute ${lib.concatStringsSep "." el.path} is used, which is not allowed.
                  Libraries should use the generic ${lib.concatStringsSep "." genericPath} instead''
              else if utils.versionTreeLib.library.isVersionPrefixOf stringVersionPrefix packageSetVersions.${name} then
                lib.warn ''
                  In ${value.path}, the attribute ${lib.concatStringsSep "." el.path} is accessed, which is specific to version ${stringVersionPrefix} of ${name}.
                  It should be preferred to use ${lib.concatStringsSep "." genericPath} instead''
                  passthru
              else
                lib.warn ''
                  In ${value.path}, the attribute ${lib.concatStringsSep "." el.path} is used when it shouldn't.
                  to use ${name} version ${stringVersionPrefix}, set packagesets.${name}.app.version = "${stringVersionPrefix}"'' alternate;

            redactingList = selfAttr: lib.concatMap (name:
              map (el: {
                path = el.path;
                value = redact selfAttr name el;
              }) packageSets.${name}.attrPaths
            ) (lib.attrNames packageSets);

            redactingSet = lib.mapAttrs (name: values:
              trace "redacting" 3 "Redacting attribute ${name} in nixpkgs"
              utils.attrs.updateAttrByPaths (map (el: el // { path = lib.tail el.path; }) values) (localVersions.baseScope.${name} or {})
            ) (lib.groupBy (x: lib.head x.path) (redactingList [ "baseScope" ]));

            ownCallPackage = utils.scopeList.callPackageWith (createScopes true);

            callPackage = utils.scopeList.callPackageWith (createScopes false);

            ownOutput = {
              # Allows getting back to the file that was used with e.g. `nix-instantiate --eval -A foo._floxPath`
              # Note that we let the callPackage result override this because builders
              # like flox.importNix are able to provide a more accurate file location
              _floxPath = value.path;
            } // ownCallPackage value.path { };
          in trace "redacting" 3 "Redacting set has these toplevel attributes: ${trace.showValue (lib.attrNames redactingSet)}" trace "calling" 8
            "Auto-calling package ${pname}"
          ownOutput)) spec.funs);



      outputs =
        let

          shallowOutputSet = spec:
            let
              shallowOutputs = createSet spec (lib.getAttrFromPath spec.path myPkgs);

              canonicalResult = utils.attrs.hydraSetAttrByPath spec.recurse spec.path
                shallowOutputs;

            in trace "outputs" 7 (lib.attrNames shallowOutputs) /*[
              {
                path = spec.path;
                value = shallowOutputs;
              }
            ];*/
            canonicalResult;#if spec ? aliasedPath then aliasedResult else canonicalResult;

          deepOutputSet = spec:
            let
              # This "fishes" out the packages that we deeply overlaid out of the resulting package set.
              deepOutputs = builtins.intersectAttrs spec.funs (lib.getAttrFromPath spec.defaultPath myPkgs);

            in trace "outputs" 7 (lib.attrNames deepOutputs) deepOutputs;

          shallowOutputs = map shallowOutputSet (lib.filter (x: x.funs != {}) outputSpecs.shallow);
          deepOutputs = map deepOutputSet (lib.filter (x: x.funs != {}) outputSpecs.deep);
          result = mergeSets (deepOutputs ++ shallowOutputs);
        in result;

      baseScope = utils.attrs.smartMerge trace (myPkgs // myPkgs.xorg) outputs;

    in {
      pkgs = myPkgs;
      inherit channels outputs baseScope;
    }));

    /*
    - When e.g. python3Packages is used from the arguments, and python 3 isn't the default version, give a warning
      Should suggest the fix of creating config.nix and setting packageSets.python.app.version = "3"
      Should also suggest the fix of using pythonPackages instead, indicating that version X will be used in that case
    - If it is the default version, allow it, because it allows copy-pasting expressions from nixpkgs directly
    - Same for channels.*.python3Packages
    - Allow changing warnings to errors
    - Only allow above for applications. Libraries will have to use pythonPackages always, error otherwise

    - Also allow enforcing the config.nix app vs lib thing
      Don't give access to package sets unless it is declared in config.nix
      The only inferred thing is e.g. python.type = "lib" from pythonPackages/*

    - Don't give any warnings/errors when accessing python3Packages from channel output
    - Only add the hydra recursion at the end and for roo
    */

in trace "channel" 3 "Evaluating, being imported from ${parentArgs.name}" versionSetSpecific)
