# Arguments for the channel file in floxpkgs
{ name ? null
, topdir
# FIXME: Deprecation warning
, extraOverlays ? null
, dependencies ?
  if builtins.pathExists (topdir + "/channels.json")
  then builtins.fromJSON (builtins.readFile (topdir + "/channels.json"))
  else []
, conflictResolution ? {}
}@chanArgs:

# Arguments for the command line
{ name ? null, debugVerbosity ? 0
  # JSON string of a `<channelName> -> <projectName> -> <srcpath>` mapping. This overrides the sources used by these channels/projects to the given paths.
, sourceOverrideJson ? "{}", _return ? "outputs"
  # Used to detect whether this default.nix is a channel (by inspecting function arguments)
, _isFloxChannel ? throw "This argument isn't meant to be accessed"
  # When evaluating for an attributes _floxPath, passing a lower number in
  # this argument allows for still getting a result in case of failing
  # evaluation, at the expense of a potentially less precise result. The
  # highest number not giving evaluation failures should be used
, _floxPathDepth ? 2
  # Allow passing other arguments for nixpkgs pkgs/top-level/release-lib.nix compatibility
, ... }@args:
let topdir' = topdir;
in let
  # To prevent any accidental imports into the store, and to make sure it's a string, not a path
  topdir = toString topdir';

  nixpkgsArgs = removeAttrs args [
    "name"
    "debugVerbosity"
    "_return"
    "sourceOverrideJson"
    "_isFloxChannel"
  ];

  # We only import nixpkgs once with an overlay that adds all channels, which is
  # also used as a base set for all channels themselves
  pkgs = import <nixpkgs> nixpkgsArgs;
  inherit (pkgs) lib;

  withVerbosity = level: fun: val:
    if debugVerbosity >= level then fun val else val;

  # A list of { name; success | failure } entries, representing heuristics used
  # to determine the channel name, in the order of preference
  #
  # See https://github.com/flox/floxpkgs/blob/staging/docs/expl/name-inference.md
  # for an explanation of why this is done
  nameHeuristics = let
    f = name: value:
      let
        result = /*if value ? success then
          let
            # Find a channel mapping in NIX_PATH that matches the name
            # This is case-insensitive because GitHub usernames are as well
            found =
              lib.findFirst (e: lib.toLower e.name == lib.toLower value.success)
              null channelFloxpkgsList;
          in if found != null then {
            success = found.name;
          } else {
            success = lib.warn
              "Inferred channel name ${value.success} using heuristic ${name}, but no entry for this channel found in NIX_PATH"
              value.success;
          }
        else*/
          value;
      in result // { inherit name; };

    heuristics = lib.mapAttrs f {
      chanArgs = if chanArgs ? name then {
        success = chanArgs.name;
      } else {
        failure = ''No "name" defined in the floxpkgs default.nix'';
      };
      cmdArgs = if args ? name then {
        success = args.name;
      } else {
        failure = ''No "name" passed with `--argstr name <channel name>`'';
      };
      baseName = if dirOf topdir == builtins.storeDir then {
        failure = "topdir is in /nix/store, basename is nonsensical";
      } else if baseNameOf topdir != "floxpkgs" then {
        success = baseNameOf topdir;
      } else {
        failure = ''Directory name of topdir is just "floxpkgs"'';
      };
      gitConfig = import ./nameFromGit.nix { inherit lib topdir; };
      #nixPath = let
      #  matchingEntries = lib.filter (e: e.path == topdir) channelFloxpkgsList;
      #  matchingNames = lib.unique (map (e: e.name) matchingEntries);
      #in if lib.length matchingNames == 0 then {
      #  failure = "No entries in NIX_PATH match path ${topdir}";
      #} else if lib.length matchingNames == 1 then {
      #  success = lib.elemAt matchingNames 0;
      #} else {
      #  failure = "Multiple entries in NIX_PATH match path ${topdir}";
      #};
    };
    ordered = [
      heuristics.chanArgs
      heuristics.cmdArgs
      #heuristics.nixPath
      heuristics.baseName
      heuristics.gitConfig
    ];
  in ordered;

  # The warning to issue when no name heuristic was successful
  fallbackNameWarning = ''
    Channel name could not be inferred because all heuristics failed:
    ${lib.concatMapStringsSep "\n" (h: "- ${h.name}: ${h.failure}")
    nameHeuristics}
    Using channel name "_unknown" instead. Because of this, channels dependent on your channel won't use your local uncommitted changes, and you will get failures if attempting to use sources from this channel.
  '';

  # The name as determined by the first successful name heuristic
  name = let
    fallback = {
      name = "fallback";
      success = lib.warn fallbackNameWarning "_unknown";
    };
    firstSuccess = lib.findFirst (e: e ? success) fallback nameHeuristics;
  in withVerbosity 2 (builtins.trace
    "Determined root channel name to be ${firstSuccess.success} with heuristic ${firstSuccess.name}")
  firstSuccess.success;

  myChannelArgs = {
    inherit name topdir extraOverlays dependencies;
    inherit _floxPathDepth;
  };

  closure =
    let
      root = {
        key = name;
        value = myChannelArgs;
      };

      getChannel = name: import (builtins.findFile builtins.nixPath name) {
        inherit name;
        _return = "channelArguments";
      };

      operator = entry: map (name:
        if name == "nixpkgs"
        then throw "Channel ${entry.key} has \"nixpkgs\" specified as a dependency, which is not necessary"
        else {
          key = name;
          value = getChannel name;
        }
      ) entry.value.dependencies;

      result = builtins.genericClosure {
        startSet = [ root ];
        operator = operator;
      };
    in result;

  dependencyGraph = pkgs.runCommandNoCC "floxpkgs-${name}-dependency-graph" {
    graph = ''
      digraph {
        "${name}" [shape=box];
      ${lib.concatMapStrings (entry:
        lib.concatMapStrings (dep:
          "  \"${entry.key}\" -> \"${dep}\";\n"
        ) entry.value.dependencies
      ) closure}}
    '';
    passAsFile = [ "graph" ];
    nativeBuildInputs = [ pkgs.graphviz ];
  } ''
    mkdir -p "$out"
    mv "$graphPath" "$out/graph.dot"
    dot -Tpng "$out/graph.dot" -Gdpi=250 -o "$out/graph.png"
    cat <<EOF > $out/view
    #!${pkgs.runtimeShell}
    export PATH=${lib.makeBinPath [ pkgs.xdot pkgs.graphviz ]}
    exec xdot $out/graph.dot
    EOF
    chmod +x $out/view
  '';

  #importChannelSrc = name: fun:
  #  fun {
  #    inherit name;
  #    _return = "channelArguments";
  #  };

  #channelArgs = lib.mapAttrs importChannelSrc channelFloxpkgs // {
  #  ${name} = myChannelArgs;
  #};

  #outputFun = import ./output.nix {
  #  inherit outputFun channelArgs pkgs withVerbosity;
  #  sourceOverrides = builtins.fromJSON sourceOverrideJson;
  #};

  # Turns a directory into an attribute set.
  # Files with a .nix suffix get turned into an attribute name without the
  # suffix. Directories get turned into an attribute of their name directly.
  # If there is both a .nix file and a directory with the same name, the file
  # takes precedence. The context argument is a string shown in trace messages
  # Each value in the resulting attribute sets has attributes
  # - value: The Nix value of the file or of the default.nix file in the directory
  # - deep: In case of directories, whether there is a deep-override file within it. For files always false
  # - path: The path to the Nix directory/file that was imported
  # - type: The file type, either "regular" for files or "directory" for directories
  dirToAttrs = context: dir:
    let
      exists = builtins.pathExists dir;

      importPath = name: type:
        let path = dir + "/${name}";
        in {
          directory = lib.nameValuePair name {
            deep = builtins.pathExists (path + "/deep-override");
            inherit path type;
          };

          regular = if lib.hasSuffix ".nix" name then
            lib.nameValuePair (lib.removeSuffix ".nix" name) {
              deep = false;
              inherit path type;
            }
          else
            null;
        }.${type} or (throw "Can't auto-call file type ${type} at ${toString path}");

      # Mapping from <package name> -> { value = <package fun>; deep = <bool>; }
      # This caches the imports of the auto-called package files, such that they don't need to be imported for every version separately
      entries = lib.filter (v: v != null)
        (lib.attrValues (lib.mapAttrs importPath (builtins.readDir dir)));

      # Regular files should be preferred over directories, so that e.g.
      # foo.nix can be used to declare a further import of the foo directory
      entryAttrs =
        lib.listToAttrs (lib.sort (a: b: a.value.type == "regular") entries);

      message = ''
        ${context} Importing all Nix expressions from directory "${
          toString dir
        }"'' + withVerbosity 6
        (_: ". Attributes: ${toString (lib.attrNames entryAttrs)}") "";

      result = if exists then
        withVerbosity 4 (builtins.trace message) entryAttrs
      else
        withVerbosity 5 (builtins.trace
          "${context} Not importing any Nix expressions because `${
            toString dir
          }` does not exist") { };

    in result;

  rootChannel = name;

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
  packageSetFuns = prefix: subpath:
    let

      #entries = lib.concatMap (packageSet:
      #  let packageSetValue = packageSets.${packageSet}; in
      #  lib.concatMap (channelEntry:
      #    let packages = dirToAttrs "packageSet ${packageSet}" (channelEntry.value.topdir + "/${packageSet}"); in
      #    map (pname: {
      #      #map (version: {
      #        inherit packageSet pname;# version;
      #        inherit (packages.${pname}) deep path;
      #        #attr = packageSetValue.versions.${version}.canonicalPath ++ [ pname ];
      #        channel = channelEntry.key;
      #      #}) (lib.attrNames packageSetValue.versions)
      #    }) (lib.attrNames packages)
      #  ) closure
      #) (lib.attrNames packageSets);

      # [{ channel, name, value }]
      entries =
        let
          f = entry:
            let
              fun = name: value: {
                inherit (value) deep;
                inherit name;
                value = {
                  channel = entry.key;
                  path = value.path;
                };
              };
              attrs = dirToAttrs "[channel ${entry.key}] [packageSet ${subpath}]" (entry.value.topdir + "/${subpath}");
            in
              lib.mapAttrsToList fun attrs;

          result = lib.concatMap f closure;
          split = lib.partition (entry: entry.deep) result;
        in split;

      # Note: These are attributes potentially containing a null value, in which case the ones from nixpkgs should be propagated
      # We don't want to filter out the null's because that causes it to be strict
      deep = lib.mapAttrs (resolve true) (lib.groupBy (entry: entry.name) entries.right);
      shallow = lib.mapAttrs (resolve false) (lib.groupBy (entry: entry.name) entries.wrong);

      # TODO: Move to channels root default.nix
      # If multiple channels define the same package, this channel should use the one from the channel specified here
      conflictResolution = {
        pkgs.kerberos = "systems";
        pkgs.hello = "infinisil";
        pkgs.gnupg = "infinisil";
        pkgs.dotfiles = "flox-examples";
        pythonPackages.requests = "nixpkgs";
      };

      resolve = overridesNixpkgs: name: entries:
        let
          path = prefix ++ [ name ];
          existsInNixpkgs = lib.hasAttrByPath path pkgs;
          attrs = lib.listToAttrs (map (entry: lib.nameValuePair entry.value.channel entry.value) entries) // lib.optionalAttrs existsInNixpkgs {
            nixpkgs = null;
          };
          options = "Options are [ ${lib.concatStringsSep ", " (lib.attrNames attrs)} ]";
        in
        # Deeply overriding packages that don't exist in nixpkgs doesn't make much sense,
        # and it's also unsafe, because nixpkgs can change behavior depending on the presence of an attribute,
        # without accessing the value itself (in which we could throw an error that conflict resolution is needed)
        if overridesNixpkgs && ! existsInNixpkgs then throw "Can't deeply override an attribute (${lib.concatStringsSep "." path}) that doesn't exist in nixpkgs"
        # No need to resolve conflict if we specified it in our own channel
        else if attrs ? ${rootChannel} then attrs.${rootChannel}
        # If a conflict resolution value was provided
        else if conflictResolution ? ${subpath}.${name} then
          attrs.${conflictResolution.${subpath}.${name}} or
          (throw "conflictResolution specified ${conflictResolution.${subpath}.${name}} for ${subpath}.${name}, but that option doesn't exist. ${options}")
        else if lib.length (lib.attrNames attrs) == 1 then lib.head (lib.attrValues attrs)
        # If we have more entries, throw an error that the conflict needs to be resolved
        else throw "conflictResolution needs to be provided for ${subpath}.${name}. ${options}";

    in {
      inherit deep shallow;
    };

  #entries = lib.concatMap (packageSet:
  #  let packageSetValue = packageSets.${packageSet}; in
  #  lib.concatMap (channelEntry:
  #    let packages = dirToAttrs "packageSet ${packageSet}" (channelEntry.value.topdir + "/${packageSet}"); in
  #    lib.concatMap (pname:
  #      map (version: {
  #        inherit packageSet version;
  #        inherit (packages.${pname}) deep path;
  #        attr = packageSetValue.versions.${version}.canonicalPath ++ [ pname ];
  #        channel = channelEntry.key;
  #      }) (lib.attrNames packageSetValue.versions)
  #    ) (lib.attrNames packages)
  #  ) closure
  #) (lib.attrNames packageSets);

  # For every package set, for every version, for every channel
  # Generate a
  # {
  #   packageSet = "<packageSet>";
  #   version = "<version>";
  #   channel = "<channel>";
  #   deep = "<deep>";
  #   path = "<path>";
  #   attribute = "<attr>";
  # }

  # Then split into deep and not deep
  # To resolve, first group them by the canonicalPath
  # Then resolve separately under each one

  #split = lib.partition (entry: entry.deep) entries;

  # :: List Any ->
  #g = null;


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

  result = lib.mapAttrs (setName: packageSet: lib.mapAttrs (version: versionInfo: packageSetFuns setName versionInfo.canonicalPath) packageSet.versions)packageSets;




  /*
  ## Package specifications

  A package specification is a structure containing all the necessary
  information of a package for it to be usable by a dependent channel.

  It contains these fields

  {
    # Whether this package should be deeply overridden. If true, this
    # causes it to be injected into nixpkgs via an overlay
    deep = <bool>;

    # Which channel (or nixpkgs), if any, this package is extended from. When the
    # same package attribute is used in the expression as an argument, this
    # is the channel it refers to
    extends = null | "nixpkgs" | <channel>;

    # The path to the package expression
    exprPath = <path>;
  }
  */

  # The dependencies of this channel, in the form { <channel> = null; }
  # Includes nixpkgs, doesn't include own channel
  dependencyAttrs = removeAttrs (lib.genAttrs dependencies (name: null)) [ name ] // {
    nixpkgs = null;
  };

  /*
  Returns all the package specifications in our own channel. To determine the
  `extends` fields for each package, it is necessary to know which other
  channels provide the same package, which is why this function takes a
  `packageChannels` argument. This argument is passed by the root channel, in
  order to not duplicate the work of determining its value.
  */
  ownPackageSpecs = packageChannels: lib.mapAttrs (setName: packageSet:
    lib.mapAttrs (pname: value: {
      deep = value.deep;
      exprPath = value.path;
      extends =
        let
          # Since we got the packageChannels from the root channel to share
          # work, we will however also have a potential superset of only our
          # own dependencies. We don't want non-dependencies to influence
          # which channel we extend from though, so we limit the channels
          # that contain the same package to the ones we depend on
          # Note that we only allow immediate dependencies here because ideally
          # a channel would not depend on transitive attributes
          attrs = lib.attrNames (builtins.intersectAttrs dependencyAttrs packageChannels.${setName}.${pname});
          result =
            # If this channel specifies a conflict resolution for this package, use that directly
            if conflictResolution ? ${setName}.${pname} then conflictResolution.${setName}.${pname}
            # Otherwise, if no channel (or nixpkgs) has this attribute, we can't extend from anywhere
            else if lib.length attrs == 0 then null
            # But if there's only a single channel (or nixpkgs) providing it, we use that directly, no need for conflict resolution
            else if lib.length attrs == 1 then lib.head attrs
            else throw "Needs super conflict resolution for ${setName}.${pname} in channel ${name}, ${toString attrs}";
        in result;
    }) (dirToAttrs setName (topdir + "/${setName}"))
  ) packageSets;


  /*
  Gives a package specification for each package in each channel.

  {
    <channel>.<packageSet>.<pname> = <package specification>;
  }
  */
  channelPackageSpecs = lib.listToAttrs (map (entry: {
    name = entry.key;
    # Gets the package specs of each channel, passing it the packageChannels
    # evaluated from the root channel to share work
    value = import entry.value.topdir { _return = "ownPackageSpecs"; } packageChannels;
  }) closure);

  /*
  Lists all channels (including nixpkgs) that contain a given package

  This value is passed to all TODO functions in all channels for them to be
  able to efficiently decide the `extends` of all the channels packages.

  This is later also going to be used by the root channel to decide where to
  get packages from.

  {
    <packageSet>.<pname> = {
      # Only if nixpkgs contains this package
      nixpkgs = null;
      # For all the channels that contain this package
      <channel> = null;
    };
  }
  */
  packageChannels = lib.mapAttrs (setName: packageSet:
    let
      packages = lib.concatMap (channel:
        lib.mapAttrsToList (pname: value: {
          inherit pname;
          name = channel;
          value = null;
        }) channelPackageSpecs.${channel}.${setName}
      ) (lib.attrNames channelPackageSpecs);

      result = lib.mapAttrs (name: values:
        lib.listToAttrs values
        # Note that this relies on the fact that pkgs ? x == pkgs.pkgs ? x
        // lib.optionalAttrs (pkgs ? ${setName}.${name}) {
          nixpkgs = null;
        }
      ) (lib.groupBy (p: p.pname) packages);
    in result
  ) packageSets;

  channelPackageSpecsList = lib.concatMap (channel:
    lib.concatMap (packageSet:
      map (pname: channelPackageSpecs.${channel}.${packageSet}.${pname} // {
        inherit channel packageSet pname;
      }) (lib.attrNames channelPackageSpecs.${channel}.${packageSet})
    ) (lib.attrNames channelPackageSpecs.${channel})
  ) (lib.attrNames channelPackageSpecs);

  split = lib.partition (spec: spec.deep) channelPackageSpecsList;

  deepPackageSetSpecs = lib.mapAttrs (setName: packageSet:
    let
      packageList = lib.concatLists (lib.mapAttrsToList (channelName: channel:
        lib.mapAttrsToList (pname: value: {
          channel = channelName;
          inherit pname;
          value = value;
        }) channel.${setName}
      ) channelPackageSpecs);
    in lib.groupBy (entry: entry.pname) packageList
  ) packageSets;

  packageChains = lib.mapAttrs (setName: setValue:
    lib.mapAttrs (pname: channels:
      let
        existsInNixpkgs = channels ? nixpkgs;
        channelList = lib.attrNames (removeAttrs channels [ "nixpkgs" ]);
        split = lib.partition (channel: channelPackageSpecs.${channel}.${setName}.${pname}.deep) channelList;

        #resolve = overridesNixpkgs: entries:
        #  let
        #    attrs = entries ++ lib.optional existsInNixpkgs "nixpkgs";
        #    #attrs = lib.listToAttrs (map (entry: lib.nameValuePair entry.value.channel entry.value) entries) // lib.optionalAttrs existsInNixpkgs {
        #    #  nixpkgs = null;
        #    #};
        #    options = "Options are [ ${lib.concatStringsSep ", " (lib.attrNames attrs)} ]";
        #  in
        #  # Deeply overriding packages that don't exist in nixpkgs doesn't make much sense,
        #  # and it's also unsafe, because nixpkgs can change behavior depending on the presence of an attribute,
        #  # without accessing the value itself (in which we could throw an error that conflict resolution is needed)
        #  if overridesNixpkgs && ! existsInNixpkgs then throw "Can't deeply override an attribute (${lib.concatStringsSep "." [setName pname]}) that doesn't exist in nixpkgs"
        #  # No need to resolve conflict if we specified it in our own channel
        #  else if attrs ? ${rootChannel} then attrs.${rootChannel}
        #  # If a conflict resolution value was provided
        #  else if conflictResolution ? ${setName}.${pname} then
        #    attrs.${conflictResolution.${setName}.${pname}} or
        #    (throw "conflictResolution specified ${conflictResolution.${setName}.${pname}} for ${setName}.${pname}, but that option doesn't exist. ${options}")
        #  else if lib.length (lib.attrNames attrs) == 1 then lib.head (lib.attrValues attrs)
        #  # If we have more entries, throw an error that the conflict needs to be resolved
        #  else throw "conflictResolution needs to be provided for ${setName}.${pname}. ${options}";

        deepRoot = deep: entries:
          let
            buildChain = origin: channel:
              if channel == null then
                if deep then "Can't deeply override attribute ${setName}.${pname} that doesn't exist in nixpkgs"
                else []
              else if channel == "nixpkgs" then [ "nixpkgs" ]
              else if ! channelPackageSpecs ? ${channel} then throw "Channel ${channel} as specified in ${origin} doesn't exist"
              else if ! lib.elem channel entries then []
              else if ! channelPackageSpecs.${channel}.${setName} ? ${pname} then throw "Package ${pname} doesn't exist in channel ${channel}"
              else builtins.trace "Calling buildChain for ${channel}, ${setName}, ${pname}" (buildChain channel channelPackageSpecs.${channel}.${setName}.${pname}.extends ++ [ channel ]);

            result =
              if entries == [] then []
              # Otherwise, if some channel overrides it, disallow that if the package doesn't exist in nixpkgs already
              #else if deep && ! existsInNixpkgs then throw "Can't deeply override attribute that doesn't exist"
              # The root channel takes precedence
              else if lib.elem rootChannel entries then buildChain rootChannel rootChannel
              else if conflictResolution ? ${setName}.${pname} then buildChain rootChannel conflictResolution.${setName}.${pname} # TODO: Validate that this option exists
              else if lib.length entries == 1 then buildChain rootChannel (lib.head entries)
              else throw "conflictResolution needs to be provided for ${setName}.${pname} in channel ${rootChannel}. Options are ${toString entries}";
          in result;

        getChain = deep: channel:
          if channel == "nixpkgs" then [ "nixpkgs" ]
          else if channel == null then []
          else builtins.trace "Appending ${channel} to chain for ${setName}.${pname}" (getChain deep (channelPackageSpecs.${channel}.${setName}.${pname}.extends or null) ++ [ channel ]);

      in {
        deep = deepRoot true split.right;
        shallow = deepRoot false split.wrong;
      }
    ) setValue
  ) packageChannels;

  # TODO: Inject all channels
  baseScope = pkgs;



  # Evaluate name early so that name inference warnings get displayed at the start, and not just once we depend on another channel
in builtins.seq name {
  outputs = packageChains;
  inherit ownPackageSpecs;
  inherit packageChannels;
  inherit packageSets;
  #outputs = packageSetFuns [ "pythonPackages" ] "pythonPackages";
  inherit dependencyGraph;
  channelArguments = myChannelArgs;
}.${_return}
