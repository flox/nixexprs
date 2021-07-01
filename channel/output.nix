# Returns the auto-generated output of a channel
# TODO: Add debug logs
{ pkgs, outputFun, channelArgs, withVerbosity, sourceOverrides }:
let
  inherit (pkgs) lib;

  pregenPath = toString (<nixpkgs-pregen> + "/package-sets.json");
  pregenResult = if builtins.pathExists pregenPath then
    withVerbosity 1 (builtins.trace "Reusing pregenerated ${pregenPath}")
    (lib.importJSON pregenPath)
  else
    lib.warn
    "Path ${pregenPath} doesn't exist, won't be able to use precomputed result, evaluation will be slow"
    (import ./package-sets.nix {
      inherit lib;
      pregenerate = true;
      nixpkgs = <nixpkgs>;
    });

  packageSets = import ./package-sets.nix {
    inherit lib pregenResult;
    pregenerate = false;
  };

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

in parentOverlays: parentArgs: myArgs:
let
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


  # TODO: What if you want to override e.g. pkgs.xorg.libX11. Make sure to recurse into attributes
  toplevel = {
    name = "toplevel";
    recurse = true;
    deepOverride = a: b: b;
    path = [ ];
    extraScope = { };
    channels = channelOutputs;
    funs = packageSetFuns "toplevel" "pkgs";
  };

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
              ${spec.callScopeAttr} = if set != null then
                set
                # maybe TODO: Try out all aliases to see if any of them have a matching version
              else
                throw "Channel ${name} did not provide attribute path `${
                  lib.concatStringsSep "." paths.canonicalPath
                }`";
            }) channelOutputs;

          packageSetScope = lib.getAttrFromPath paths.canonicalPath baseScope
            // {
              ${spec.callScopeAttr} = packageSetScope;
            };

          output = path: {
            name = setName;
            inherit path;
            recurse = paths.recurse;
            deepOverride = spec.deepOverride;
            extraScope = packageSetScope;
            inherit channels funs;
          };

          aliasOutput = path: {
            name = setName;
            inherit path;
            aliasedPath = paths.canonicalPath;
          };

        in [ (output paths.canonicalPath) ] ++ map aliasOutput paths.aliases;

      results =
        lib.concatLists (lib.mapAttrsToList versionOutput spec.versions);

    in lib.optionals (funs.deep != { } || funs.shallow != { }) results;

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

     {
       name = <name for this output set>;
       path = <attribute path where this set should end up in the channels result>;
       aliasedPath = <the aliased path the above path should point to>;
     }
  */
  outputSpecs = [ toplevel ]
    ++ lib.concatLists (lib.mapAttrsToList packageSetOutputs packageSets);

  /* The outputs of each channel as imported by this channel.

     This calls this very function of this file (outputFun) again, but with this
     channels overlays and arguments passed as parentOverlays/parentArgs. This
     means that there is no caching of channel outputs between different accessors
     of that channel. In turn however this allows deep overrides over the whole
     channel dependency tree.
  */
  channelOutputs = let
    original =
      lib.mapAttrs (name: args: outputFun myOverlays myArgs args) channelArgs;
    # Also allow each channel to be referenced by its all-lowercase name
    lowercased =
      lib.mapAttrs' (name: lib.nameValuePair (lib.toLower name)) original;
  in original // lowercased;

  createSet = spec: super:
    lib.mapAttrs (pname: value:
      let
        localMeta = meta // {
          inherit (spec) channels;

          inherit scope;

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
              # If we're evaluating for a _floxPath, only let the result of an
              # importNix call influence the _floxPath with a _floxPathDepth
              # greater or equal to 2
              # Note that technically we could pass a nested importNix into the
              # scope which increases the depth by one more, though this
              # doesn't seem to be very beneficial in most cases
            } // lib.optionalAttrs (myArgs._floxPathDepth >= 2)
            (ownCallPackage fullPathChecked { });
        };

        # TODO: Probably more efficient to directly inspect function arguments and fill these entries out.
        # A callPackage abstraction that allows specifying multiple attribute sets might be nice
        createScope = isOwn:
          baseScope // spec.extraScope // lib.optionalAttrs isOwn {
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
          # If we're evaluating for a _floxPath, only let the result of an
          # package call influence the _floxPath with a _floxPathDepth
          # greater or equal to 1
        } // lib.optionalAttrs (myArgs._floxPathDepth >= 1)
          (ownCallPackage value.path { });
      in withVerbosity 8 (builtins.trace
        "[channel ${myArgs.name}] [packageSet ${spec.name}] Auto-calling package ${pname}")
      ownOutput);

  # All the overlays that should be applied to the pkgs base set for this
  # channels evaluation (and all the channels it imports)
  myOverlays = let

    deepSpecTrace = spec:
      builtins.trace "[channel ${myArgs.name}] [path ${
        lib.concatStringsSep "." spec.path
      }] Deeply overriding attributes ${
        toString (lib.attrNames spec.funs.deep)
      }" spec;

    # Only the output sets that need a deep override
    # We do this so we can avoid having to add an overlay if not necessary
    deepOutputSpecs = withVerbosity 6 (map deepSpecTrace)
      (lib.filter (o: o.funs.deep or { } != { }) outputSpecs);

    deepOverlay = self: super:
      let
        deepOverlaySet = spec:
          overlaySet super spec.path (superSet:
            withVerbosity 5 (builtins.trace "[channel ${myArgs.name}] [path ${
                lib.concatStringsSep "." spec.path
              }] Creating overriding package set") spec.deepOverride superSet
            (createSet spec superSet spec.funs.deep));
      in mergeSets (map deepOverlaySet deepOutputSpecs);

    # See https://github.com/flox/floxpkgs/blob/staging/docs/expl/deep-overrides.md#channel-dependencies for why this order seems to be reversed
  in lib.optional (deepOutputSpecs != [ ]) deepOverlay ++ myArgs.extraOverlays
  ++ parentOverlays;

  # The resulting pkgs set of this channel, needed for the function arguments of
  # this channels packages, and for extracting outputs that were deeply overridden
  myPkgs = pkgs.appendOverlays myOverlays;

  outputSet = spec:
    let
      packageSet = lib.getAttrFromPath spec.path myPkgs;

      outputTrace = source:
        lib.mapAttrs (name:
          builtins.trace "[channel ${myArgs.name}] [path ${
            lib.concatStringsSep "." spec.path
          }] Output attribute ${name} comes from ${source}");

      shallowOutputs = withVerbosity 7 (outputTrace "shallow output")
        (createSet spec packageSet spec.funs.shallow);

      # This "fishes" out the packages that we deeply overlaid out of the resulting package set.
      deepOutputs = withVerbosity 7 (outputTrace "deep override")
        (builtins.intersectAttrs spec.funs.deep packageSet);

      canonicalResult = hydraSetAttrByPath spec.recurse spec.path
        (shallowOutputs // deepOutputs);

      aliasedResult = hydraSetAttrByPath false spec.path
        (lib.getAttrFromPath spec.aliasedPath outputs);

    in if spec ? aliasedPath then aliasedResult else canonicalResult;

  outputs = withVerbosity 6 (builtins.trace "Got output spec paths: ${
      lib.concatMapStringsSep ", " (spec: lib.concatStringsSep "." spec.path)
      outputSpecs
    }") (mergeSets (map outputSet outputSpecs));

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

  # TODO: Splicing for cross compilation?? Take inspiration from mkScope in pkgs/development/haskell-modules/make-package-set.nix
  baseScope = smartMerge (myPkgs // myPkgs.xorg) outputs;

in withVerbosity 3 (builtins.trace
  ("[channel ${myArgs.name}] Evaluating, being imported from ${parentArgs.name}"))
outputs
