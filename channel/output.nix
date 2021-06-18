# Returns the auto-generated output of a channel
# TODO: Add debug logs
{ pkgs, outputFun, channelArgs, withVerbosity, sourceOverrides, packageSets, versionTreeLib }:
let
  inherit (pkgs) lib;

  # TODO: Better error
  redactedError = path: lib.setAttrByPath path (throw "Tried to access redacted path ${lib.concatStringsSep "." path}");

  /*
  Redacting:
  - For channels and toplevel, for all package sets and all versions, remove their canonicalPath's and aliasedPath's, and the package sets callScopeAttr
  - For toplevel additionally remove all toplevelBlacklist's

  Repopulating:
  - For all allowed package sets,
    - For toplevel and channels, set callScopeAttr to the set
    - For toplevel, also use populateToplevel
  */
  redactingSet =
    let
      lists = lib.concatLists (lib.mapAttrsToList (name: value:
        let
          versionSets = lib.concatLists (lib.mapAttrsToList (name: value:
            [ (redactedError value.path) ]# ++ map redactedError value.aliases
          ) value.versions);
        in [ (redactedError [ value.callScopeAttr ]) ] ++ versionSets ++ map redactedError (map lib.singleton (lib.attrNames value.aliases))
      ) packageSets);
      result = mergeSets lists;
    in builtins.trace (toString (lib.attrNames result)) result;

  toplevelRedactingSet =
    let
      lists = lib.concatLists (lib.mapAttrsToList (name: value:
        map redactedError value.toplevelBlacklist
      ) packageSets);
      result = mergeSets lists;
    in builtins.trace (toString (lib.attrNames result)) result;

  # TODO: Error if conflicting paths. Maybe on the package-sets.nix side already though
  mergeSets = lib.foldl' lib.recursiveUpdate { };

  /* Sets a value at a specific attribute path, while merging the attributes along that path with the ones from super, suitable for overlays.

     Note: Because overlays implicitly use `super //` on the attributes, we don't want to have `super //` on the toplevel. We also don't want `super.<path> // <value>` on the lowest level, as we want to override the attribute path completely.

     Examples:
       overlaySet super [] value == value
       overlaySet super [ "foo" ] value == { foo = value; }
       overlaySet super [ "foo" "bar" ] value == { foo = super.foo // { bar = value; }; }
  */
  overlaySet = super: path: valueMod:
    let
      subname = lib.head path;
      subsuper = super.${subname};
      subvalue = subsuper // overlaySet subsuper (lib.tail path) valueMod;
    in if path == [ ] then valueMod super else { ${subname} = subvalue; };

  /* Same as setAttrByPath, except that lib.recurseIntoAttrs is applied to each path element, such that hydra recurses into the given value

     Examples:
       hydraSetAttrByPath recurse [] value = value
       hydraSetAttrByPath recurse [ "foo" ] value = { foo = value // { recurseIntoAttrs = true; }; }
       hydraSetAttrByPath recurse [ "foo" "bar" ] value = { foo = { recurseIntoAttrs = true; bar = value // { recurseIntoAttrs = true; }; }; }
  */
  hydraSetAttrByPath = recurse: attrPath: value:
    if attrPath == [ ] then
      value
    else {
      ${lib.head attrPath} =
        hydraSetAttrByPath recurse (lib.tail attrPath) value // {
          recurseForDerivations = recurse;
        };
      };

  updateAttrByPath = path: value: set:
    if path == [] then value
    else set // {
      ${lib.head path} = updateAttrByPath (lib.tail path) value (set.${lib.head path} or {});
    };

  inherit (import ./memoizeFunctionParameters.nix { inherit lib; }) memoizeFunctionParameters;

in parentOverlays: parentArgs: myArgs: libraryVersions:
let

  appVersionTrees = lib.mapAttrs (name: value:
    versionTreeLib.setDefault "" (myArgs.defaultLibraryVersions.${name} or "") value.versionTree
  ) packageSets;

  # Merges attribute sets recursively, but not recursing into derivations,
  # and error if a derivation is overridden with a non-derivation, or the other way around
  smartMerge = lib.recursiveUpdateUntil (path: l: r:
    let
      lDrv = lib.isDerivation l;
      rDrv = lib.isDerivation r;
      prettyPath = lib.concatStringsSep "." path;
      warning = "Overriding ${lib.optionalString (!lDrv) "non-"}derivation ${
          lib.concatStringsSep "." path
        } in nixpkgs"
        + " with a ${lib.optionalString (!rDrv) "non-"}derivation in channel";
    in if lDrv == rDrv then
    # If both sides are derivations, override completely
      if rDrv then
        withVerbosity 7 (builtins.trace
          "[channel ${myArgs.name}] [smartMergePath ${prettyPath}] Overriding because both sides are derivations")
        true
        # If both sides are attribute sets, merge recursively
      else if lib.isAttrs l && lib.isAttrs r then
        withVerbosity 7 (builtins.trace
          "[channel ${myArgs.name}] [smartMergePath ${prettyPath}] Recursing because both sides are attribute sets")
        false
        # Otherwise, override completely
      else
        withVerbosity 7 (builtins.trace
          "[channel ${myArgs.name}] [smartMergePath ${prettyPath}] Overriding because left is ${
            builtins.typeOf l
          } and right is ${builtins.typeOf r}") true
    else
      lib.warn warning true);

  # Turns a directory into an attribute set.
  # Files with a .nix suffix get turned into an attribute name without the
  # suffix. Directories get turned into an attribute of their name directly.
  # If there is both a .nix file and a directory with the same name, the file
  # takes precedence. The context argument is a string shown in trace messages
  # Each value in the resulting attribute sets has attributes
  # - value: The Nix value of the file or of the default.nix file in the directory
  # - deep: In case of directories, whether there is a deep-override file within it. For files always false
  # - file: The path to the Nix file that was imported
  # - type: The file type, either "regular" for files or "directory" for directories
  dirToAttrs = context: dir:
    let
      exists = builtins.pathExists dir;

      importPath = name: type:
        let path = dir + "/${name}";
        in {
          directory = lib.nameValuePair name {
            # TODO: Allow specified deepOverride = true in config.nix
            deep = builtins.pathExists (path + "/deep-override");
            config = if builtins.pathExists (path + "/config.nix") then import (path + "/config.nix") else {};
            inherit path type;
          };

          regular = if lib.hasSuffix ".nix" name then
            lib.nameValuePair (lib.removeSuffix ".nix" name) {
              deep = false;
              config = {};
              inherit path type;
            }
          else
            null;
        }.${type} or (throw "Can't auto-call file type ${type}");

      # Mapping from <package name> -> { value = <package fun>; deep = <bool>; }
      # This caches the imports of the auto-called package files, such that they don't need to be imported for every version separately
      entries = lib.filter (v: v != null)
        (lib.attrValues (lib.mapAttrs importPath (builtins.readDir dir)));

      # Regular files should be preferred over directories, so that e.g.
      # foo.nix can be used to declare a further import of the foo directory
      entryAttrs =
        lib.listToAttrs (lib.sort (a: b: a.value.type == "regular") entries);

      message = ''
        [channel ${myArgs.name}] [${context}] Importing all Nix expressions from directory "${
          toString dir
        }"'' + withVerbosity 6
        (_: ". Attributes: ${toString (lib.attrNames entryAttrs)}") "";

      result = if exists then
        withVerbosity 4 (builtins.trace message) entryAttrs
      else
        withVerbosity 5 (builtins.trace
          "[channel ${myArgs.name}] [${context}] Not importing any Nix expressions because `${
            toString dir
          }` does not exist") { };

    in result;

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
          output = path: version: {
            name = setName;
            inherit path;
            defaultPath = [ spec.callScopeAttr ];
            deepOverride = spec.deepOverride;
            extraScope = spec.callScopeAttr;
            funs = funs.deep;
            libraryVersions.${setName} = version;
            defaultTypes.${setName} = "lib";
          };

          defaultOutput =
            output [ spec.callScopeAttr ] (versionTreeLib.queryDefault "" packageSets.${setName}.versionTree);


          aliasOutput = alias: aliasValue:
            output [ alias ] (versionTreeLib.queryDefault aliasValue packageSets.${setName}.versionTree);

          versionOutput = version: versionInfo:
            output versionInfo.path version;

        in [ defaultOutput ]
          ++ lib.mapAttrsToList aliasOutput spec.aliases
          ++ lib.mapAttrsToList versionOutput spec.versions;

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
  versionSetSpecific =
    let
      original = pkgs.appendOverlays myOverlays;
      # TODO: Make sure this throws the correct errors
      redacted = lib.recursiveUpdate (lib.recursiveUpdate original redactingSet) toplevelRedactingSet;
    in memoizeFunctionParameters allPackageSetVersions (packageSetVersions:
      {
        pkgs =
          # TODO: If app, not only allow access from pythonPackages, but also python${major}Packages (aliases) and python${major}${minor}Packages (canonicalPath)
          lib.foldl' (set: name:
            let
              version = packageSetVersions.${name};
              setInfo = packageSets.${name};
              canonicalPath = setInfo.versions.${version}.path or
                (throw "No version ${version} for ${name}, available ones are [ ${lib.concatMapStringsSep ", " (x: "\"${x}\"") (lib.attrNames setInfo.versions)} ]");
              canonicalSet = lib.getAttrFromPath canonicalPath original;

              withCallScopeAttr = updateAttrByPath [ setInfo.callScopeAttr ] canonicalSet set;
              result = withCallScopeAttr // setInfo.populateToplevel canonicalSet;
            in
              builtins.seq version (builtins.trace "Allowing access to ${lib.concatStringsSep "." canonicalPath} from ${setInfo.callScopeAttr}"
                # Force early version resolution error
                result)
          ) redacted (lib.attrNames packageSetVersions);

        channels =
          let
            cased = lib.mapAttrs (name: args:
              outputFun myOverlays myArgs args packageSetVersions
            ) channelArgs;

            lowercased =
              lib.mapAttrs' (name: lib.nameValuePair (lib.toLower name)) cased;
          in cased // lowercased;
      }
    );

  createSet = spec: super:
    lib.mapAttrs (pname: value:
      let

        packageSetVersions = lib.mapAttrs (name: pvalue:
          let
            config = value.config.packageSets.${name} or {};
            type = config.type or spec.defaultType.${name} or "app";
            version = {
              app = versionTreeLib.queryDefault (config.app.version or "") appVersionTrees.${name};
              lib = spec.libraryVersions.${name} or libraryVersions.${name};
            }.${type} or
              (throw ''
                In ${value.path}/config.nix, packageSets.${name}.type is specified to be "${config.type}", which is not a valid value.
                Select either "app" or "lib"
              '');
          in version
        ) packageSets;

        inherit (lib.debug.traceSeq packageSetVersions versionSetSpecific packageSetVersions) pkgs channels;

        # TODO: Splicing for cross compilation?? Take inspiration from mkScope in pkgs/development/haskell-modules/make-package-set.nix
        baseScope = smartMerge (pkgs // pkgs.xorg) channels.${myArgs.name};

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

        # TODO: Probably more efficient to directly inspect function arguments and fill these entries out.
        # A callPackage abstraction that allows specifying multiple attribute sets might be nice
        createScope = isOwn:
          baseScope // extraScope // lib.optionalAttrs isOwn {
            ${pname} = super.${pname} or (throw
              "${pname} is accessed in ${value.path}, but is not defined because nixpkgs has no ${pname} attribute");
          } // {
            # These attributes are reserved
            meta = localMeta;
            inherit (localMeta) channels;
            flox = localMeta.channels.flox or (throw
              "Attempted to access flox channel from channel ${myArgs.name}, but no flox channel is present in NIX_PATH");
            inherit callPackage;
          };

        ownCallPackage = lib.callPackageWith (createScope true);

        scope = createScope false;
        callPackage = lib.callPackageWith scope;

        ownOutput = {
          # Allows getting back to the file that was used with e.g. `nix-instantiate --eval -A foo._floxPath`
          # Note that we let the callPackage result override this because builders
          # like flox.importNix are able to provide a more accurate file location
          _floxPath = value.path;
        } // ownCallPackage value.path { };
      in withVerbosity 8 (builtins.trace
        "[channel ${myArgs.name}] [packageSet ${spec.name}] Auto-calling package ${pname}")
      ownOutput) spec.funs;

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

  shallowOutputSet = spec:
    let
      packageSet = lib.getAttrFromPath spec.path (versionSetSpecific libraryVersions).pkgs;

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
      packageSet = lib.getAttrFromPath spec.defaultPath (versionSetSpecific libraryVersions).pkgs;

      outputTrace = source:
        lib.mapAttrs (name:
          builtins.trace "[channel ${myArgs.name}] [path ${
            lib.concatStringsSep "." spec.path
          }] Output attribute ${name} comes from ${source}");


      # This "fishes" out the packages that we deeply overlaid out of the resulting package set.
      deepOutputs = withVerbosity 7 (outputTrace "deep override")
        (builtins.intersectAttrs spec.funs packageSet);

    in deepOutputs;

  outputs =
    let
      message = "Got output spec paths: ${
        lib.concatMapStringsSep ", " (spec: lib.concatStringsSep "." spec.path)
        outputSpecs
      }";
      shallowOutputs = map shallowOutputSet (lib.filter (x: x.funs != {}) outputSpecs.shallow);
      deepOutputs = map deepOutputSet (lib.filter (x: x.funs != {}) outputSpecs.deep);
      result = mergeSets (deepOutputs ++ shallowOutputs);
    in withVerbosity 6 (builtins.trace message) result;

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


in withVerbosity 3 (builtins.trace
  ("[channel ${myArgs.name}] Evaluating, being imported from ${parentArgs.name}"))
outputs
