# Arguments for the channel file in nixexprs
{ name ? null
, topdir
, needsParentChannelAccess ? false
, extraOverlays ? []
}@chanArgs:
# Arguments for the command line
{ name ? null
, debugVerbosity ? 0
, return ? "outputs"
, srcpath ? ""
, manifest_json ? ""
, manifest ? ""
}@args:
let
  topdir' = topdir;
in
let
  # To prevent any accidental imports into the store, and to make sure it's a string, not a path
  topdir = toString topdir';

  # We only import nixpkgs once with an overlay that adds all channels, which is
  # also used as a base set for all channels themselves
  pkgs = import <nixpkgs> {};
  inherit (pkgs) lib;

  # A list of { name; success | failure } entries, representing heuristics used
  # to determine the channel name, in the order of preference
  nameHeuristics =
    let
      f = name: value:
        let
          result =
            if value ? success then
              if channelNixexprs ? ${value.success} then value
              else { failure = "Found channel name ${value.success}, but no entry for this channel found in NIX_PATH"; }
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
            matchingEntries = lib.filterAttrs (name: path: path == topdir) channelNixexprs;
            matchingNames = lib.unique (lib.attrNames matchingEntries);
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
    in withVerbosity 2 (builtins.trace "Determined channel name to be \"${firstSuccess.success}\" with heuristic ${firstSuccess.name}") firstSuccess.success;

  withVerbosity = level: fun: val: if debugVerbosity >= level then fun val else val;

  myChannelArgs = {
    inherit name needsParentChannelAccess topdir extraOverlays args;
  };

  # Mapping from channel name to a path to its nixexprs root
  # Search through both prefixed and non-prefixed paths in NIX_PATH
  channelNixexprs =
    let
      expandEntry = e:
        if e.prefix != "" then [{
          name = e.prefix;
          value = e.path;
        }]
        # TODO: Change flox wrapper to do this expansion
        else lib.mapAttrsToList (name: type: {
          inherit name;
          value = e.path + "/${name}";
        }) (builtins.readDir e.path);
      result = lib.listToAttrs (lib.concatMap expandEntry builtins.nixPath);
    in withVerbosity 1 (builtins.trace "Found these channel-like entries in NIX_PATH: ${toString (lib.attrNames result)}") result;

  importChannelSrc = name: src: withVerbosity 1
    (builtins.trace "Importing channel `${name}` from `${toString src}`")
    (import src { inherit name; return = "channelArguments"; });

  channelArgs = lib.mapAttrs importChannelSrc channelNixexprs // {
    ${name} = myChannelArgs;
  };

  outputFun = import ./output.nix { inherit pkgs; };

  # The pkgs set for a specific channel
  channelPkgs = parentChannel: { name, needsParentChannelAccess, topdir, extraOverlays, args }:
    let

      channelOutputs = lib.mapAttrs (name: value: value.floxInternal.outputs) channels.${name};

      channelOverlay = self: super: {
        floxInternal = {
          parentChannel =
            if needsParentChannelAccess then parentChannel
            else throw "Channel \"${name}\" tried to access `floxInternal.parentChannel`, but this is not allowed by default. To allow this, set\n  needsParentChannelAccess = true\nin the `default.nix` of channel \"${name}\"";
          inherit args withVerbosity;
        };
      };
      overlays = [
        channelOverlay
        (outputFun { inherit name topdir channelOutputs; })
      ] ++ extraOverlays;
    in pkgs.appendOverlays overlays;

  parentIndependentChannels = lib.mapAttrs (_: args:
    channelPkgs null args
  ) channelArgs;

  channels = lib.mapAttrs (parent: _:
    lib.mapAttrs (name: args:
      # If the channel to import doesn't require access to the parent channel,
      # don't reimport it again, just use the shared one from the parentIndependentChannel mapping
      if args.needsParentChannelAccess
      then channelPkgs parent args
      else parentIndependentChannels.${name}
    ) channelArgs
  ) channelArgs;

  outputs = channels.${name}.${name}.floxInternal.outputs;

in {
  inherit outputs;
  channelArguments = myChannelArgs;
}.${return}
