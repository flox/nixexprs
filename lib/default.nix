# Arguments for the channel file in nixexprs
{ name ? null
, topdir
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
      heuristics = lib.mapAttrs (name: value: value // { inherit name; }) {
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
    Using channel name "unknown" instead. Because of this, channels dependent on your channel won't use your local uncommitted changes
  '';

  # The name as determined by the first successful name heuristic
  name =
    let
      fallback = { name = "fallback"; success = lib.warn fallbackNameWarning "unknown"; };
      firstSuccess = lib.findFirst (e: e ? success) fallback nameHeuristics;
    in withVerbosity 2 (builtins.trace "Determined channel name to be \"${firstSuccess.success}\" with heuristic ${firstSuccess.name}") firstSuccess.success;

  withVerbosity = level: fun: val: if debugVerbosity >= level then fun val else val;

  myChannelArgs = {
    inherit name topdir extraOverlays args;
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


  # The pkgs set for a specific channel
  channelPkgs = parentChannel: { name, topdir, extraOverlays, args }:
    let

      channels' = lib.mapAttrs (name: value: value.floxInternal.outputs) channels.${name};

      channelOverlay = self: super: {
        floxInternal = {
          inherit parentChannel args withVerbosity;
          outputs = {};

          # Merges pkgs and own channel outputs recursively
          mainScope = lib.recursiveUpdateUntil (path: l: r:
            let
              lDrv = lib.isDerivation l;
              rDrv = lib.isDerivation r;
            in
              if lDrv == rDrv then if rDrv then true else ! lib.isAttrs rDrv
              else throw ("Trying to override ${lib.optionalString (!lDrv) "non-"}derivation in nixpkgs"
                + " with a ${lib.optionalString (!rDrv) "non-"}derivation in channel")
          ) self self.floxInternal.outputs // {
            channels = channels';
            flox = channels'.flox or (throw "Attempted to access flox channel from channel ${name}, but no flox channel is present in NIX_PATH");
          };
        };
      };
      overlays = [ channelOverlay ]
        ++ lib.optional (builtins.pathExists (topdir + "/pkgs")) (import ./auto/toplevel.nix (topdir + "/pkgs"))
        ++ extraOverlays;
    in pkgs.appendOverlays overlays;


  channels = lib.mapAttrs (parent: _:
    lib.mapAttrs (_: args:
      channelPkgs parent args
    ) channelArgs
  ) channelArgs;

  outputs = channels.${name}.${name}.floxInternal.outputs;

in {
  inherit outputs;
  channelArguments = myChannelArgs;
}.${return}
