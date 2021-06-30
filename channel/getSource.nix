{ sourceOverrides, lib, fetchgit, buildPackages }:
channel:
let
  channelSourceOverrides = sourceOverrides.${channel} or { };
  # Set the src and version variables based on project.
  # Recall that flox calls this expression with --argstr sourceOverrideJson '{ ... }',
  # so that needs to take precedence over all other sources of src.
in project:
let
  # The source is provided with `--argstr sourceOverrideJson`
  channelOverrideComponents = let
    # This fetches all uncommitted changes, without untracked files
    src = builtins.fetchGit channelSourceOverrides.${project};
  in {
    inherit src;
    origversion = "manual";
    # If the passed source isn't dirty (revCount != 0), we can use some additional info
    versionSuffix =
      lib.optionalString (src.revCount != 0) "-git${toString src.shortRev}";
    extraInfo =
      lib.optionalAttrs (src.revCount != 0) { inherit (src) rev revCount; };
  };
in overrides:
let

  # The following three definitions are three different ways of getting the
  # source. Each of these defines an attribute set with all the info needed from
  # the source, including:
  # - src: The path to the source
  # - origversion: The original version of the source
  # - versionSuffix: An optional version suffix
  # - extraInfo: Any additional source attributes used for identifying it

  # The source is provided via the `src` argument
  argumentOverrideComponents = {
    src = overrides.src;
    # We need to get a sensible version from somewhere
    origversion = overrides.version or (throw ("In ${
        let pos = builtins.unsafeGetAttrPos "src" overrides;
        in pos.file + ":" + toString pos.line
      }"
      + " a source override was specified, which also requires a `version = ` to be assigned."));
    versionSuffix = "";
    extraInfo = { };
  };

  metaComponents = let
    # The channel name is set to _unknown in channel/default.nix if it couldn't be inferred
    # A warning for why it couldn't be inferred will already have been thrown
    channelSources = if channel == "_unknown" then
      throw ''
        Could not find source for project "${project}" because the channel name is unknown.''
    else
      builtins.findFile builtins.nixPath "${channel}-meta/srcs";

    # toString the channelSources to ensure it's not a path, which could lead to importing it into the store
    repoInfoPath = toString channelSources + "/${project}.json";

    repoInfo = if builtins.pathExists repoInfoPath then
      lib.importJSON repoInfoPath
    else
      throw (''
        Could not find source for project "${project}" in channel "${channel}". Are webhooks for''
        + " that repository set up? If they are, make sure to commit at least once so the webhook triggers.");

    rev = overrides.rev or "master";

    # Choose the source for this derivation from the "srcs" hash found
    # in the json data. If the user has provided the "rev" keyword then
    # look for that revision either by explicit revision or branch name,
    # and default to falling back to the revision referred to by the master
    # branch.
    gitHash =
      # If the passed rev is a branch, use the git hash that branch points to
      if repoInfo.branches ? ${rev} then
        repoInfo.branches.${rev}
        # If the passed rev looks like a git hash already, use that directly
      else if builtins.match "[0-9a-f]{40}" rev != null then
        rev
        # Otherwise complain
      else
        throw (''
          Could not find branch "${rev}" in ${repoInfoPath}, and could not find such a Git hash either.''
          # But also detect if the rev might be a shortened git hash
          + lib.optionalString (builtins.match "[0-9a-f]{6,}" rev != null)
          " This looks like a shortened Git hash though, pass the full one instead");

    # The attribute set for a specific git hash, originally generated by nix-prefetch-git, but amended with `version` and `revision` attributes
    gitHashInfo = repoInfo.srcs.${gitHash} or (throw
      ''Could not find git hash "${gitHash}" in ${repoInfoPath}'');

  in {
    src = fetchgit ({
      # To make sure the path matches (so we can reuse the cached version),
      # extract the very same store path name.
      # 44 is the length of "/nix/store/" plus the 32-char hash plus a "-"
      name = builtins.substring 44 (-1) gitHashInfo.path;
      inherit (gitHashInfo) url rev sha256;
    } // lib.optionalAttrs (gitHashInfo ? subdir) {
      # If there is a subdir attribute, the result should be rooted at that dir
      postFetch = ''
        tmp=$(mktemp -d)
        mv "$out" "$tmp"/src
        mv "$tmp"/src/${lib.escapeShellArg gitHashInfo.subdir} "$out"
      '';
    });

    # We assume that both .version and .revision exist in gitHashInfo
    origversion = gitHashInfo.version;
    versionSuffix = "-r${toString gitHashInfo.revision}";
    extraInfo = { inherit (gitHashInfo) url rev sha256 date; };
  };

  components = let
    # Determine which components to use by prioritizing `--argstr sourceOverrideJson`
    # over override arguments over `<$channel-meta/srcs>`
    original = if channelSourceOverrides ? ${project} then
      channelOverrideComponents
    else if overrides ? src then
      argumentOverrideComponents
    else
      metaComponents;

    # But let the user override all of them
    final = original // {
      # Small exception: The version gets mapped to origversion
      origversion = overrides.version or original.origversion;
      versionSuffix = overrides.versionSuffix or original.versionSuffix;
      extraInfo = original.extraInfo // overrides.extraInfo or { };
    };
  in final;

  # The resulting attributes
  result = rec {
    inherit project;
    inherit (components) src origversion;
    pname = overrides.pname or project;
    version = components.origversion + components.versionSuffix;
    name = overrides.name or (pname + "-" + version);
  };

  infoJson = builtins.toJSON (removeAttrs result [ "src" ] // {
    # TODO: This is the eval-time system, use the build-time system instead.
    system = builtins.currentSystem;
  } // components.extraInfo);

  # Return all known source information on stdout with a command, for easy embedding into $out
  createInfoJson = ''
    (
      ${lib.getBin buildPackages.jq}/bin/jq -n \
      --arg buildDate "$(date -Iseconds)" \
      --argjson info ${lib.escapeShellArg infoJson} \
      '$info | .buildDate |= $buildDate'
    )'';
  # No newline at the end, because we want builders to be able to pass additional redirections!

in result // { inherit infoJson createInfoJson; }
