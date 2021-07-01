# Arguments for the channel file in floxpkgs
{ name ? null
, topdir
# FIXME: Deprecation warning
, extraOverlays ? null
, dependencies ?
  if builtins.pathExists (topdir + "/channels.json")
  then builtins.fromJSON (builtins.readFile (topdir + "/channels.json"))
  else []
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

  closure = builtins.genericClosure {
    startSet = [{
      key = name;
      inherit name;
      value = myChannelArgs;
    }];
    operator = entry: map (name: {
      key = name;
      inherit name;
      value = import (builtins.findFile builtins.nixPath name) {
        inherit name;
        _return = "channelArguments";
      };
    }) entry.value.dependencies;
  };

  dependencyGraph = pkgs.runCommandNoCC "floxpkgs-${name}-dependency-graph" {
    graph = ''
      digraph {
        "${name}" [shape=box];
      ${lib.concatMapStrings (entry:
        lib.concatMapStrings (dep:
          "  \"${entry.name}\" -> \"${dep}\";\n"
        ) entry.value.dependencies
      ) closure}}
    '';
    passAsFile = [ "graph" ];
    nativeBuildInputs = [ pkgs.graphviz ];
  } ''
    dot -Tpng "$graphPath" -Gdpi=300 -o $out
  '';

  allChannels = builtins.listToAttrs closure;

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
      #dir = myArgs.topdir + "/${subpath}";

      #entries = lib.mapAttrsToList lib.nameValuePair
      #  (dirToAttrs "packageSet ${setName}" dir);

      # { <channel> = { <name> = <entry>; }; }
      #entries = lib.mapAttrs (name: args:
      #  dirToAttrs "[channel ${name}] [packageSet ${setName}]" args.topdir
      #) allChannels;
      # flip
      # => { <name> = { <channel> = <entry>; }; }
      # resolve
      # => { <name> = <entry>; }
      # deep-partition

      # [ { channel = ...; name = ...; value = <entry>; } ]
      entries = lib.concatMap (entry:
        lib.mapAttrsToList (name: value: {
          channel = entry.name;
          inherit name;
          value = value // {
            channel = entry.name;
          };
        }) (dirToAttrs "[channel ${name}] [packageSet ${setName}]" (entry.value.topdir + "/${subpath}"))
      ) closure;

      resolve = name: entries: if lib.length entries > 1 then throw "You need to resolve entry ${name}" else builtins.trace "No need to resolve entry ${name}, it only occurs in ${(lib.head entries).channel}" (lib.head entries);

      # { <name> = <entry>; }
      resolved = lib.mapAttrsToList resolve (lib.groupBy (entry: entry.name) entries);


      parts = lib.mapAttrs (n: v: lib.listToAttrs (map (e: e // { value = { inherit (e.value) channel path; }; }) v))
        (lib.partition (e: e.value.deep) resolved);

    in {
      deep = parts.right;
      shallow = parts.wrong;
    };

  # Evaluate name early so that name inference warnings get displayed at the start, and not just once we depend on another channel
in builtins.seq name {
  outputs = packageSetFuns "toplevel" "pkgs";
  inherit dependencyGraph;
  channelArguments = myChannelArgs;
}.${_return}
