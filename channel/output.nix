# Returns the auto-generated output of a channel
# TODO: Add debug logs
{ pkgs, outputFun, channelArgs, withVerbosity, sourceOverrides, packageSets, versionTreeLib }:
let
  inherit (pkgs) lib;

  # TODO: Better error
  #redactedError = path: lib.setAttrByPath path (throw "Tried to access redacted path ${lib.concatStringsSep "." path}");

  /*
  Redacting:
  - For toplevel, for all package sets and all versions, remove their canonicalPath's and aliasedPath's, and the package sets callScopeAttr
  - For toplevel additionally remove all toplevelBlacklist's

  Repopulating:
  - For all allowed package sets,
    - For toplevel, set callScopeAttr to the set
    - For toplevel, also use populateToplevel
  */
  #redactingSet =
  #  let
  #    lists = lib.concatLists (lib.mapAttrsToList (name: value:
  #      let
  #        versionSets = lib.concatLists (lib.mapAttrsToList (name: value:
  #          [ (redactedError value.path) ]# ++ map redactedError value.aliases
  #        ) value.versions);
  #      in [ (redactedError [ value.callScopeAttr ]) ] ++ versionSets ++ map redactedError (map lib.singleton (lib.attrNames value.aliases))
  #    ) packageSets);
  #    result = mergeSets lists;
  #  in builtins.trace (toString (lib.attrNames result)) result;

  #toplevelRedactingSet =
  #  let
  #    lists = lib.concatLists (lib.mapAttrsToList (name: value:
  #      map redactedError value.toplevelBlacklist
  #    ) packageSets);
  #    result = mergeSets lists;
  #  in builtins.trace (toString (lib.attrNames result)) result;

  # TODO: Error if conflicting paths. Maybe on the package-sets.nix side already though
  mergeSets = lib.foldl' lib.recursiveUpdate { };

in parentOverlays: parentArgs: myArgs:
let

  appVersionTrees = lib.mapAttrs (name: value:
    versionTreeLib.setDefault "" (myArgs.defaultLibraryVersions.${name} or "") value.versionTree
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
  packageSetFuns = setName: subpath:
    let
      dir = myArgs.topdir + "/${subpath}";

      entries = lib.mapAttrsToList lib.nameValuePair
        (dirToAttrs "packageSet ${setName}" dir);

      parts = lib.mapAttrs (n: v: lib.listToAttrs v)
        (lib.partition (e: e.value.deep) entries);

    in {
      deep = parts.right;
      shallow = parts.wrong;
    };

  toplevel =
    let
      funs = packageSetFuns "toplevel" "pkgs";
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
        # TODO: Nest extraScope, funs, path, libraryVersions under createSet attribute, to indicate that it's used by that function
        name = "toplevel";
        recurse = true;
        path = [ ];
        extraScope = null;
        funs = funs.shallow;
        libraryVersions = {};
        defaultTypes = {};
      }];
    };

  packageSetOutputs = setName: spec:
    let

      funs = packageSetFuns setName spec.callScopeAttr;

      deepOutputs =
        let
          output = el: {
            name = setName;
            inherit (el) path;
            defaultPath = [ spec.callScopeAttr ];
            deepOverride = spec.deepOverride;
            extraScope = spec.callScopeAttr;
            funs = funs.deep;
            libraryVersions.${setName} = versionTreeLib.queryDefault el.versionPrefix packageSets.${setName}.versionTree;
            defaultTypes.${setName} = "lib";
          };

        in map output spec.packageSetAttrPaths;

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
    };

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
    inherit withVerbosity;
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
  versionSetSpecific = memoizeFunctionParameters allPackageSetVersions (libraryVersions:
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
              overlaySet super spec.path (superSet:
                withVerbosity 5 (builtins.trace "[channel ${myArgs.name}] [path ${
                    lib.concatStringsSep "." spec.path
                  }] Creating overriding package set") spec.deepOverride superSet
                (createSet spec superSet));
          in mergeSets (map deepOverlaySet outputSpecs.deep);

        # See https://github.com/flox/floxpkgs/blob/staging/docs/expl/deep-overrides.md#channel-dependencies for why this order seems to be reversed
      in lib.optional (lib.any (x: x.funs != {}) outputSpecs.deep) deepOverlay ++ myArgs.extraOverlays
        ++ parentOverlays;


      myPkgs =
        let
          original = pkgs.appendOverlays myOverlays;

          # TODO: Make sure this throws the correct errors
          redacted = lib.recursiveUpdate (lib.recursiveUpdate original redactingSet) toplevelRedactingSet;
        in
        # TODO: If app, not only allow access from pythonPackages, but also python${major}Packages (aliases) and python${major}${minor}Packages (canonicalPath)
        lib.foldl' (set: name:
          let
            version = libraryVersions.${name};
            setInfo = packageSets.${name};
            canonicalPath = setInfo.versions.${version} or
              (throw "No version ${version} for ${name}, available ones are [ ${lib.concatMapStringsSep ", " (x: "\"${x}\"") (lib.attrNames setInfo.versions)} ]");
            canonicalSet = lib.getAttrFromPath canonicalPath original;

            withCallScopeAttr = updateAttrByPath [ setInfo.callScopeAttr ] canonicalSet set;
            result = withCallScopeAttr // setInfo.populateToplevel canonicalSet;
          in
            builtins.seq version (builtins.trace "Allowing access to ${lib.concatStringsSep "." canonicalPath} from ${setInfo.callScopeAttr}"
              # Force early version resolution error
              result)
        ) redacted (lib.attrNames libraryVersions);


      channels =
        let
          cased = lib.mapAttrs (name: args:
            outputFun myOverlays myArgs args libraryVersions
          ) channelArgs;

          lowercased =
            lib.mapAttrs' (name: lib.nameValuePair (lib.toLower name)) cased;
        in cased // lowercased;

      createSet = spec: super:
        lib.mapAttrs (pname: value:
          let

            defaultedConfig = lib.mapAttrs (name: pvalue:
              let
                config = value.config.packageSets.${name} or {};
                type = config.type or spec.defaultType.${name} or "app";
                version = {
                  app = {
                    app.version = versionTreeLib.queryDefault (config.app.version or "") appVersionTrees.${name};
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

            # repopulate, takes a set, a set of package versions, and a function to get the same set for different package set versions
            # Returns the set, but where there's aliases for all package sets according to the version tree
            # Also takes a function that specifies how

            #repopulate = fun: lib.concatLists (lib.mapAttrsToList (setName: setValue:
            #  lib.mapAttrsToList (version: versionValue: let path = versionValue.path; in {
            #    path = path;
            #    value = fun path setName version;
            #  }) setValue.versions
            #  ++ lib.mapAttrsToList (aliasAttr: aliasVersionPrefix: let path = [ aliasAttr ]; in {
            #    path = path;
            #    value = fun path setName aliasVersionPrefix;
            #  }) setValue.aliases
            #) packageSets);

            #rep = accessPath: let base = lib.getAttrFromPath accessPath localVersions; in lib.foldl' (acc: el: updateAttrByPath el.path el.value acc) base (repopulate (path: set: versionPrefix:
            #  let callScopeAttr = packageSets.${set}.callScopeAttr; in
            #  if defaultedConfig.${set}.type == "app" then
            #    if versionTreeLib.isVersionPrefixOf versionPrefix packageSetVersions.${set}
            #    then base.${callScopeAttr}
            #    else
            #      let
            #        alternateVersions = packageSetVersions // {
            #          ${set} = versionTreeLib.queryDefault versionPrefix appVersionTrees.${set};
            #        };
            #      in lib.warn "In ${value.path}, the attribute ${lib.concatStringsSep "." path} is used when it shouldn't. To use ${set} version ${versionPrefix}, set packageSets.${set}.app.version = \"${versionPrefix}\""
            #        (lib.getAttrFromPath accessPath (versionSetSpecific alternateVersions)).${callScopeAttr}
            #  else throw "In ${value.path}, the attribute ${lib.concatStringsSep "." path} is used, which is not allowed. Libraries should use the generic ${callScopeAttr} instead"
            #));

            #baseScope = lib.foldl' (acc: name:
            #  let pvalue = packageSets.${name}; version = packageSetVersions.${name}; in
            #  lib.foldl' (acc: el:
            #    let
            #      result =
            #        if defaultedConfig.${name}.type == "app" then
            #          if versionTreeLib.isVersionPrefixOf el.versionPrefix version
            #          then localVersions.baseScope.${pvalue.callScopeAttr}
            #          else
            #            let
            #              alternateVersions = packageSetVersions // {
            #                ${name} = versionTreeLib.queryDefault el.versionPrefix appVersionTrees.${name};
            #              };
            #            in lib.warn "In ${value.path}, the attribute ${lib.concatStringsSep "." el.path} is used when it shouldn't. To use ${name} version ${el.versionPrefix}, set packageSets.${name}.app.version = \"${el.versionPrefix}\""
            #              (versionSetSpecific alternateVersions).baseScope.${pvalue.callScopeAttr}
            #        else throw "In ${value.path}, the attribute ${lib.concatStringsSep "." el.path} is used, which is not allowed. Libraries should use the generic ${pvalue.callScopeAttr} instead";
            #    in updateAttrByPath el.path result acc
            #  ) acc pvalue.packageSetAttrPaths
            #) localVersions.baseScope (lib.attrNames packageSets);

            #appRedact = file: name: el:
            #  if versionTreeLib.isVersionPrefixOf el.versionPrefix version
            #  then utils.getListAttr packageSets.${name}.callScopeAttr localVersions.baseScopeList
            #  else
            #    let
            #      alternateVersions = packageSetVersions // {
            #        ${name} = versionTreeLib.queryDefault el.versionPrefix appVersionTrees.${name};
            #      };
            #      result = utils.getListAttr packageSets.${name}.callScopeAttr (versionSetSpecific alternateVersions).baseScopeList;
            #      warning = ''
            #        In ${file}, the attribute ${lib.concatStringsSep "." el.path} is used when it shouldn't.
            #        To use ${name} version ${el.versionPrefix}, set packageSets.${name}.app.version = "${el.versionPrefix}"
            #      '';
            #    in lib.warn warning result;

            #redactingAttrs = utils.nestedListToAttrs (lib.concatLists (lib.mapAttrsToList (name: pvalue:
            #  map (el: {
            #    path = el.path;
            #    value = if isApp then appRedact value.path name el else null;
            #  }) pvalue.packageSetAttrPaths
            #  ++
            #  map (el: {
            #    path = el.path;
            #    value =
            #      if defaultedConfig.${name}.type == "app" then
            #        if versionTreeLib.isVersionPrefixOf el.versionPrefix version
            #        then utils.getListAttr pvalue.callScopeAttr localVersions.baseScopeList
            #        else
            #          let
            #            alternateVersions = packageSetVersions // {
            #              ${name} = versionTreeLib.queryDefault el.versionPrefix appVersionTrees.${name};
            #            };
            #          in lib.warn "In ${value.path}, the attribute ${lib.concatStringsSep "." el.path} is used when it shouldn't. To use ${name} version ${el.versionPrefix}, set packageSets.${name}.app.version = \"${el.versionPrefix}\""
            #            utils.getListAttr pvalue.callScopeAttr (versionSetSpecific alternateVersions).baseScopeList
            #      else throw "In ${value.path}, the attribute ${lib.concatStringsSep "." el.path} is used, which is not allowed. Libraries should use the generic ${pvalue.callScopeAttr} instead";
            #  }) pvalue.extraNixpkgsAttrPaths
            #) packageSets));
            #toplevelRedactingSet = utils.nestedListToAttrs null;

            channels = lib.mapAttrs (channel: channelValue:
              channelValue.outputs
            ) localVersions.channels;

            localVersions = versionSetSpecific packageSetVersions;

            extraScope = if spec.extraScope == null then {} else baseScope.${spec.extraScope};

            localMeta = meta // {
              inherit channels scope;

              mapDirectory = dir:
                { call ? path: callPackage path { } }:
                lib.mapAttrs (name: value: call value.path)
                (dirToAttrs "mapDirectory ${baseNameOf dir}" dir);

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

            redactingSet = lib.mapAttrs (name: values:
              utils.attrs.updateAttrByPaths values (localVersions.baseScope.${name} or {})
            ) lib.groupBy (x: lib.head x.toplevel) redactingList;

            redactingList = lib.concatLists (lib.mapAttrsToList (name: pvalue:
              let
                forApp = el:
                  if versionTreeLib.isVersionPrefixOf el.versionPrefix version
                  then lib.warn "Shouldn't access non-pythonPackages atributes" (lib.getAttrFromPath suffix localVersions.baseScope.${pvalue.callScopeAttr})
                  else
                    let
                      alternateVersions = packageSetVersions // {
                        ${name} = versionTreeLib.queryDefault el.versionPrefix appVersionTrees.${name};
                      };
                      warning = ''
                        In ${value.path}, the attribute ${lib.concatStringsSep "." el.path} is used when it shouldn't.
                        To use ${name} version ${el.versionPrefix}, set packageSets.${name}.app.version = "${el.versionPrefix}"
                      '';
                      result = lib.getAttrFromPath suffix (versionSetSpecific alternateVersions).baseScope.${pvalue.callScopeAttr};
                    in lib.warn warning result;

                forLib = el: throw ''
                  In ${value.path}, the attribute ${lib.concatStringsSep "." el.path} is used, which is not allowed.
                  Libraries should use the generic ${lib.concatStringsSep "." (lib.optional (suffix != [] && extraScope != pvalue.callScopeAttr) pvalue.callScopeAttr ++ suffix)} instead
                '';

                forAny = if defaultedConfig.${name}.type == "app" then forApp else forLib;
                result = suffix: el: {
                  toplevel = lib.head el.path;
                  path = lib.tail el.path;
                  value = forAny el;
                };
              in map (result []) pvalue.packageSetAttrPaths
              ++ map (el: result el.valueAttrPath) pvalue.extraNixpkgsAttrPaths
            ) packageSets);

            ownCallPackage = utils.scopeList.callPackage (createScope true);

            callPackage = utils.scopeList.callPackage (createScope false);

            ownOutput = {
              # Allows getting back to the file that was used with e.g. `nix-instantiate --eval -A foo._floxPath`
              # Note that we let the callPackage result override this because builders
              # like flox.importNix are able to provide a more accurate file location
              _floxPath = value.path;
            } // ownCallPackage value.path { };
          in withVerbosity 8 (builtins.trace
            "[channel ${myArgs.name}] [packageSet ${spec.name}] Auto-calling package ${pname}")
          ownOutput) spec.funs;



      outputs =
        let

          shallowOutputSet = spec:
            let
              packageSet = lib.getAttrFromPath spec.path myPkgs;

              outputTrace = source:
                lib.mapAttrs (name:
                  builtins.trace "[channel ${myArgs.name}] [path ${
                    lib.concatStringsSep "." spec.path
                  }] Output attribute ${name} comes from ${source}");

              shallowOutputs = withVerbosity 7 (outputTrace "shallow output")
                (createSet spec packageSet);

              canonicalResult = hydraSetAttrByPath spec.recurse spec.path
                (shallowOutputs /*// deepOutputs*/);

              #aliasedResult = hydraSetAttrByPath false spec.path
              #  (lib.getAttrFromPath spec.aliasedPath outputs);

            in canonicalResult;#if spec ? aliasedPath then aliasedResult else canonicalResult;

          deepOutputSet = spec:
            let
              packageSet = lib.getAttrFromPath spec.defaultPath myPkgs;

              outputTrace = source:
                lib.mapAttrs (name:
                  builtins.trace "[channel ${myArgs.name}] [path ${
                    lib.concatStringsSep "." spec.path
                  }] Output attribute ${name} comes from ${source}");


              # This "fishes" out the packages that we deeply overlaid out of the resulting package set.
              deepOutputs = withVerbosity 7 (outputTrace "deep override")
                (builtins.intersectAttrs spec.funs packageSet);

            in deepOutputs;

          message = "Got output spec paths: ${
            lib.concatMapStringsSep ", " (spec: lib.concatStringsSep "." spec.path)
            outputSpecs
          }";
          shallowOutputs = map shallowOutputSet (lib.filter (x: x.funs != {}) outputSpecs.shallow);
          deepOutputs = map deepOutputSet (lib.filter (x: x.funs != {}) outputSpecs.deep);
          result = mergeSets (deepOutputs ++ shallowOutputs);
        in withVerbosity 6 (builtins.trace message) result;

      baseScope = smartMerge (myPkgs // myPkgs.xorg) outputs;

    in {
      pkgs = myPkgs;
      inherit channels outputs baseScope;
    });

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
    - Only add the hydra recursion at the end and for root
    */


in withVerbosity 3 (builtins.trace
  ("[channel ${myArgs.name}] Evaluating, being imported from ${parentArgs.name}"))
versionSetSpecific
