let
  # The attribute argument deconstruction in Nix is weird, let's not rely on it
  # We will get defaults by checking for existence of the attribute in firstArgs/secondArgs
  default = abort "A default argument value is used when it shouldn't";
in {
# These are documented in ../docs/channel-construction.md
name ? default, topdir, extraOverlays ? default
  # TODO: Enable once update-floxpkgs doesn't rely only on channels.json
  #, dependencies ? default
, conflictResolution ? default }@firstArgs:
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
  # These are documented in ../docs/channel-construction.md
, name ? default, debugVerbosity ? default, subsystemVerbosities ? default
, sourceOverrideJson ? default
  # When evaluating for an attributes _floxPath, passing a lower number in
  # this argument allows for still getting a result in case of failing
  # evaluation, at the expense of a potentially less precise result. The
  # highest number not giving evaluation failures should be used
, _floxPathDepth ? default
  # Allow passing other arguments for nixpkgs pkgs/top-level/release-lib.nix compatibility
, ... }@secondArgs:
let
  rootResult = import ./root.nix firstArgs secondArgs;

  ownResult = import ./own.nix {
    inherit firstArgs;
    inherit (secondArgs._fromRoot) channelName lib utils trace packageSets;
  };

in if _isRoot then rootResult else ownResult
