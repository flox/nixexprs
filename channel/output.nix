# Returns the auto-generated output of a channel
# TODO: Add debug logs
{ pkgs, outputFun, channelArgs, withVerbosity }:
let
  # TODO: Pregenerate a JSON from this
  packageSets = import ./package-sets.nix { inherit pkgs; };
  inherit (pkgs) lib;


  # TODO: Error if conflicting paths. Maybe on the package-sets.nix side already though
  mergeSets = lib.foldl' lib.recursiveUpdate {};


  /*
  Sets a value at a specific attribute path, while merging the attributes along that path with the ones from super, suitable for overlays.

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
    in
      if path == [] then valueMod super
      else { ${subname} = subvalue; };

in
parentOverlays: parentArgs: myArgs:
let
  # Merges attribute sets recursively, but not recursing into derivations,
  # and error if a derivation is overridden with a non-derivation, or the other way around
  smartMerge = lib.recursiveUpdateUntil (path: l: r:
    let
      lDrv = lib.isDerivation l;
      rDrv = lib.isDerivation r;
      prettyPath = lib.concatStringsSep "." path;
      error = "Trying to override ${lib.optionalString (!lDrv) "non-"}derivation in nixpkgs"
        + " with a ${lib.optionalString (!rDrv) "non-"}derivation in channel";
    in
      if lDrv == rDrv then
        # If both sides are derivations, override completely
        if rDrv then withVerbosity 7 (builtins.trace "[channel ${myArgs.name}] [smartMergePath ${prettyPath}] Overriding because both sides are derivations") true
        # If both sides are attribute sets, merge recursively
        else if lib.isAttrs l && lib.isAttrs r then withVerbosity 7 (builtins.trace "[channel ${myArgs.name}] [smartMergePath ${prettyPath}] Recursing because both sides are attribute sets") false
        # Otherwise, override completely
        else withVerbosity 7 (builtins.trace "[channel ${myArgs.name}] [smartMergePath ${prettyPath}] Overriding because left is ${builtins.typeOf l} and right is ${builtins.typeOf r}") true
      else throw error);

  # Imports all directories and files in a subpath and returns a list of { name = <name>; value = <expression>; deep = <bool>; file = <path>; }
  /*
  Imports all directories and Nix files of the given package directory subpath. Returns
  {
    # For attributes that have { deep = true; } in their package directory (doesn't work for files)
    deep = {
      <name> = <fun>;
    };
    # For attributes that don't have { deep = true; }
    shallow = {
      <name> = <fun>;
    };
  }
  */
  packageSetFuns = setName: subpath:
    let
      dir = myArgs.topdir + "/${subpath}";
      exists = builtins.pathExists dir;

      importPath = name: type:
        {
          directory = lib.nameValuePair name {
            # TODO: Better error when there's no default.nix?
            value = import (dir + "/${name}");
            deep = builtins.pathExists (dir + "/${name}/deep-override");
            file = dir + "/${name}/default.nix";
          };

          regular =
            if lib.hasSuffix ".nix" name
            then lib.nameValuePair (lib.removeSuffix ".nix" name) {
              value = import (dir + "/${name}");
              deep = false;
              file = dir + "/${name}";
            } else null;
        }.${type} or (throw "Can't auto-call file type ${type}");

      # Mapping from <package name> -> { value = <package fun>; deep = <bool>; }
      # This caches the imports of the auto-called package files, such that they don't need to be imported for every version separately
      entries = lib.filter (v: v != null) (lib.attrValues (lib.mapAttrs importPath (builtins.readDir dir)));

      message = "[channel ${myArgs.name}] [packageSet ${setName}] Importing all Nix expressions from directory \"${toString dir}\"" + withVerbosity 6 (_: ". Attributes: ${toString (map (e: e.name) entries)}") "";

      checkedEntries = if exists
        then withVerbosity 4 (builtins.trace message) entries
        else withVerbosity 5 (builtins.trace "[channel ${myArgs.name}] [packageSet ${setName}] Not importing any Nix expressions because `${toString dir}` does not exist") [];

      parts = lib.mapAttrs (n: v: lib.listToAttrs v) (lib.partition (e: e.value.deep) checkedEntries);

    in {
      deep = parts.right;
      shallow = parts.wrong;
    };


  # TODO: What if you want to override e.g. pkgs.xorg.libX11. Make sure to recurse into attributes
  toplevel =
    let
      scope = baseScope // {
        channels = channelOutputs;
        flox = channelOutputs.flox or (throw "Attempted to access flox channel from channel ${myArgs.name}, but no flox channel is present in NIX_PATH");
      };
    in {
      deepOverride = a: b: b;
      path = [];
      packageScope = super: pname: scope // {
        ${pname} = super.${pname};
      };
      funs = packageSetFuns "toplevel" "pkgs";
    };


  createSet = name: super: packageScope: lib.mapAttrs (pname: value:
    withVerbosity 8 (builtins.trace "[channel ${myArgs.name}] [packageSet ${name}] Auto-calling package ${pname}")
      (lib.callPackageWith (packageScope super pname) value.value {}));

  packageSetOutputs = setName: spec:
    let

      funs = packageSetFuns setName spec.callScopeAttr;

      versionOutput = version: paths:
        let

          # This maps channels to e.g. have pythonPackages be the correct version
          channels = lib.mapAttrs (name: value:
            # If the dependent channel has the package set with the correct version,
            let set = lib.attrByPath paths.canonicalPath null value;
            in value // {
              ${spec.callScopeAttr} =
                if set != null then set
                # maybe TODO: Try out all aliases to see if any of them have a matching version
                else throw "Channel ${name} did not provide attribute path `${lib.concatStringsSep "." paths.canonicalPath}`";
            }
          ) channelOutputs;

          packageSetScope = lib.getAttrFromPath paths.canonicalPath baseScope;

          scope = baseScope // packageSetScope // {
            inherit channels;
            flox = channels.flox or (throw "Attempted to access flox channel from channel ${myArgs.name}, but no flox channel is present in NIX_PATH");
          };

          output = path: {
            inherit path;
            deepOverride = spec.deepOverride;
            # TODO: Probably more efficient to directly inspect function arguments and fill these entries out.
            # A callPackage abstraction that allows specifying multiple attribute sets might be nice
            packageScope = super: pname: scope // {
              ${pname} = super.${pname};
              ${spec.callScopeAttr} = packageSetScope // {
                ${pname} = super.${pname};
              };
            };
            inherit funs;
          };

          aliasOutput = path: {
            inherit path;
            aliasedPath = paths.canonicalPath;
          };

        in [ (output paths.canonicalPath) ] ++ map aliasOutput paths.aliases;

      results = lib.concatLists (lib.mapAttrsToList versionOutput spec.versions);

    in lib.optionals (funs.deep != {} || funs.shallow != {}) results;

  /*
  A list of entries describing an output set, each of the form
    {
      path = <attribute path where this set should end up in the channels result>;
      packageScope = <super: pname: The scope to call a specific package pname with>;
      deepOverride = <set: overrides: How to deeply override this output with nixpkgs overlays using the given overrides>;
      funs = <result from packageSetFuns, contains all package functions, split into deep/shallow>;
    }

    or if it's an alias definition

    {
      path = <attribute path where this set should end up in the channels result>;
      aliasedPath = <the aliased path the above path should point to>;
    }
  */
  outputSpecs = [ toplevel ] ++ lib.concatLists (lib.mapAttrsToList packageSetOutputs packageSets);

  /*
  The outputs of each channel as imported by this channel.

  This calls this very function of this file (outputFun) again, but with this
  channels overlays and arguments passed as parentOverlays/parentArgs. This
  means that there is no caching of channel outputs between different accessors
  of that channel. In turn however this allows deep overrides over the whole
  channel dependency tree.
  */
  channelOutputs =
    let
      original = lib.mapAttrs (name: args: outputFun myOverlays myArgs args) channelArgs;
    in original // lib.mapAttrs' (name: lib.nameValuePair (lib.toLower name)) original;

  # All the overlays that should be applied to the pkgs base set for this
  # channels evaluation (and all the channels it imports)
  myOverlays =
    let

      deepSpecTrace = spec: builtins.trace "[channel ${myArgs.name}] [path ${lib.concatStringsSep "." spec.path}] Deeply overriding attributes ${toString (lib.attrNames spec.funs.deep)}" spec;

      # Only the output sets that need a deep override
      # We do this so we can avoid having to add an overlay if not necessary
      deepOutputSpecs = withVerbosity 6 (map deepSpecTrace) (lib.filter (o: o.funs.deep or {} != {}) outputSpecs);

      deepOverlay = self: super:
        let
          deepOverlaySet = spec:
          overlaySet super spec.path (superSet:
            withVerbosity 5
              (builtins.trace "[channel ${myArgs.name}] [path ${lib.concatStringsSep "." spec.path}] Creating overriding package set")
              spec.deepOverride superSet (createSet spec.name superSet spec.packageScope spec.funs.deep));
        in mergeSets (map deepOverlaySet deepOutputSpecs);


    in lib.optional (deepOutputSpecs != []) deepOverlay ++ myArgs.extraOverlays ++ parentOverlays;

  # The resulting pkgs set of this channel, needed for the function arguments of
  # this channels packages, and for extracting outputs that were deeply overridden
  myPkgs = pkgs.appendOverlays myOverlays;

  outputSet = spec:
    let
      packageSet = lib.getAttrFromPath spec.path myPkgs;

      outputTrace = source: lib.mapAttrs (name: builtins.trace "[channel ${myArgs.name}] [path ${lib.concatStringsSep "." spec.path}] Output attribute ${name} comes from ${source}");

      shallowOutputs = withVerbosity 7 (outputTrace "shallow output") (createSet spec.name packageSet spec.packageScope spec.funs.shallow);

      # This "fishes" out the packages that we deeply overlayed out of the resulting package set.
      deepOutputs = withVerbosity 7 (outputTrace "deep override") (builtins.intersectAttrs spec.funs.deep packageSet);

      result = if spec ? aliasedPath
        then lib.getAttrFromPath spec.aliasedPath outputs
        else shallowOutputs // deepOutputs;

    in lib.setAttrByPath spec.path result;

  outputs = withVerbosity 6
    (builtins.trace "Got output spec paths: ${lib.concatMapStringsSep ", " (spec: lib.concatStringsSep "." spec.path) outputSpecs}") (mergeSets
    (map outputSet outputSpecs));

  # TODO: Splicing for cross compilation?? Take inspiration from mkScope in pkgs/development/haskell-modules/make-package-set.nix
  baseScope = smartMerge (myPkgs // myPkgs.xorg) outputs // {
    floxInternal = {
      importingChannelArgs = parentArgs;
      inherit withVerbosity;
    };
  };

in withVerbosity 3 (builtins.trace ("[channel ${myArgs.name}] Evaluating, being imported from ${parentArgs.name}")) outputs
