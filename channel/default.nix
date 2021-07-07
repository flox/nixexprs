let
  default = abort "A default argument value is used when it shouldn't";
in
# Arguments for the channel file in floxpkgs
{ name ? default
, topdir
, extraOverlays ? default
, dependencies ? default
, conflictResolution ? default
}@firstArgs:

# Optional arguments for command line or when imported from another channel
{

# If imported by the user from the command line, this is the root channel, and
# this flag is set to true. But if this channel is not the root channel, it is
# imported from another channel that _is_ the root, which imports this one
# with this flag set to false
  _isRoot ? true

####### This argument is only used for non-root channels #######

# Passed when _isRoot = false in order to allow imported channels to have
# access to evaluations made by the root channel
, _fromRoot ? default

####### These arguments are only used for the root channel #######

# Allows the user to provide a root channel name, overriding the name inference
, name ? default
# Default verbosity of trace messages
, debugVerbosity ? default
# Override of the verbosity of trace message for specific subsystems
, subsystemVerbosities ? default
# JSON string of a `<channelName> -> <projectName> -> <srcpath>` mapping
# This overrides the sources used by these channels/projects to the given paths
, sourceOverrideJson ? default
# When evaluating for an attributes _floxPath, passing a lower number in
# this argument allows for still getting a result in case of failing
# evaluation, at the expense of a potentially less precise result. The
# highest number not giving evaluation failures should be used
, _floxPathDepth ? default
# Allow passing other arguments for nixpkgs pkgs/top-level/release-lib.nix compatibility
, ...
}@secondArgs:
let

  rootResult = import ./root.nix firstArgs secondArgs;

  ownResult = import ./own.nix {
    inherit firstArgs;
    inherit (secondArgs._fromRoot) channelName lib utils trace packageSets packageChannels;
  };

in if _isRoot then rootResult else ownResult
