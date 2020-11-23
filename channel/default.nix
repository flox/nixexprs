# Arguments for the channel file in nixexprs
{ name ? null
, topdir
, extraOverlays ? []
}@chanArgs:

# Arguments for the command line
{ name ? null
, debugVerbosity ? 0
, return ? "outputs"
# JSON string of a `<projectName> -> <srcpath>` mapping. This overrides the sources used by these projects to the given paths.
, sourceOverrideJson ? null
# Used to detect whether this default.nix is a channel (by inspecting function arguments)
, isFloxChannel ? throw "This argument isn't meant to be accessed"
# Allow passing other arguments for nixpkgs pkgs/top-level/release-lib.nix compatibility
, ...
}@args:
let
  topdir' = topdir;
in
let
  # To prevent any accidental imports into the store, and to make sure it's a string, not a path
  topdir = toString topdir';

  nixpkgsArgs = removeAttrs args [ "name" "debugVerbosity" "return" "sourceOverridesJson" "isFloxChannel" ];

  # We only import nixpkgs once with an overlay that adds all channels, which is
  # also used as a base set for all channels themselves
  pkgs = import <nixpkgs> nixpkgsArgs;
  inherit (pkgs) lib;

  withVerbosity = level: fun: val: if debugVerbosity >= level then fun val else val;

  # A list of { name; success | failure } entries, representing heuristics used
  # to determine the channel name, in the order of preference
  nameHeuristics =
    let
      f = name: value:
        let
          result =
            if value ? success then
              let
                # Find a channel mapping in NIX_PATH that matches the name
                # This is case-insensitive because GitHub usernames are as well
                found = lib.findFirst (e: lib.toLower e.name == lib.toLower value.success) null channelNixexprsList;
              in
              if found != null then { success = found.name; }
              else {
                success = lib.warn "Inferred channel name ${value.success} using heuristic ${name}, but no entry for this channel found in NIX_PATH" value.success;
              }
            else value;
        in result // { inherit name; };

      heuristics = lib.mapAttrs f {
        chanArgs = if chanArgs ? name then { success = chanArgs.name; } else { failure = "No \"name\" defined in the nixexprs default.nix"; };
        cmdArgs = if args ? name then { success = args.name; } else { failure = "No \"name\" passed with `--argstr name <channel name>`"; };
        baseName =
          if dirOf topdir == builtins.storeDir then { failure = "topdir is in /nix/store, basename is nonsensical"; }
          else if baseNameOf topdir != "nixexprs" then { success = baseNameOf topdir; }
          else { failure = "Directory name of topdir is just \"nixexprs\""; };
        gitConfig = import ./nameFromGit.nix { inherit lib topdir; };
        nixPath =
          let
            matchingEntries = lib.filter (e: e.path == topdir) channelNixexprsList;
            matchingNames = lib.unique (map (e: e.name) matchingEntries);
          in if lib.length matchingNames == 0 then { failure = "No entries in NIX_PATH match path ${topdir}"; }
          else if lib.length matchingNames == 1 then { success = lib.elemAt matchingNames 0; }
          else { failure = "Multiple entries in NIX_PATH match path ${topdir}"; };
      };
      ordered = [
        heuristics.chanArgs
        heuristics.cmdArgs
        heuristics.nixPath
        heuristics.baseName
        heuristics.gitConfig
      ];
    in ordered;

  # The warning to issue when no name heuristic was successful
  fallbackNameWarning = ''
    Channel name could not be inferred because all heuristics failed:
    ${lib.concatMapStringsSep "\n" (h: "- ${h.name}: ${h.failure}") nameHeuristics}
    Using channel name "_unknown" instead. Because of this, channels dependent on your channel won't use your local uncommitted changes, and you will get failures if attempting to use sources from this channel.
  '';

  # The name as determined by the first successful name heuristic
  name =
    let
      fallback = { name = "fallback"; success = lib.warn fallbackNameWarning "_unknown"; };
      firstSuccess = lib.findFirst (e: e ? success) fallback nameHeuristics;
    in withVerbosity 2 (builtins.trace "Determined root channel name to be ${firstSuccess.success} with heuristic ${firstSuccess.name}") firstSuccess.success;

  myChannelArgs = {
    inherit name topdir extraOverlays args;
  };

  # List of { name, path, value } entries of channels found in NIX_PATH
  # Searches through both prefixed and non-prefixed paths in NIX_PATH
  channelNixexprsList =
    let
      expandEntry = e:
        if e.prefix != "" then [{
          name = e.prefix;
          path = e.path;
        }]
        # TODO: Change flox wrapper to do this expansion
        else lib.mapAttrsToList (name: type: {
          inherit name;
          path = e.path + "/${name}";
        }) (builtins.readDir e.path);

      pathEntries = lib.concatMap expandEntry builtins.nixPath;
      exprEntries = map (e: e // { value = import e.path; }) (lib.filter (e: builtins.pathExists (e.path + "/default.nix")) pathEntries);
      channelEntries = lib.filter (e:
        let
          isFloxChannel = builtins.tryEval (lib.isFunction e.value && (lib.functionArgs e.value) ? isFloxChannel);
          result =
            if isFloxChannel.success then
              if isFloxChannel.value then
                withVerbosity 1 (builtins.trace "[channel ${e.name}] Importing from `${toString e.path}`") true
              else
                withVerbosity 3 (builtins.trace "NIX_PATH entry ${e.name} points to path ${e.path} which is not a flox channel (${lib.generators.toPretty {} e.value}), ignoring this entry") false
            else
              withVerbosity 3 (builtins.trace "NIX_PATH entry ${e.name} points to a path ${e.path} which can't be evaluated successfully, ignoring this entry") false;
        in result
      ) exprEntries;
    in withVerbosity 1 (builtins.trace "Found these channel-like entries in NIX_PATH: ${toString (map (e: e.name) channelEntries)}") channelEntries;

  channelNixexprs = lib.listToAttrs channelNixexprsList;

  importChannelSrc = name: fun: fun { inherit name; return = "channelArguments"; };

  channelArgs = lib.mapAttrs importChannelSrc channelNixexprs // {
    ${name} = myChannelArgs;
  };

  outputFun = import ./output.nix { inherit outputFun channelArgs pkgs withVerbosity; };

in
# Evaluate name early so that name inference warnings get displayed at the start, and not just once we depend on another channel
builtins.seq name {
  outputs = outputFun [] myChannelArgs myChannelArgs;
  channelArguments = myChannelArgs;
}.${return}
