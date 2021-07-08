# flox version of stdenv.mkDerivation, enhanced to provide all the
# magic required to locate source, version and build number from
# metadata cached by the nixpkgs mechanism.

{ stdenv, lib, meta }:

# Arguments provided to flox.mkDerivation()
{ project ? null # the name of the project, required
, channel ? meta.importingChannel, ... }@args:
let
  source = meta.getChannelSource channel project args;
  # Actually create the derivation.
  floxResult = stdenv.mkDerivation (removeAttrs args [ "channel" ] // {
    inherit (source) version src name;

    # This for one sets meta.position to where the project is defined
    pos = builtins.unsafeGetAttrPos "project" args;

    # Create .flox.json file in root of package dir to record
    # details of package inputs.
    postInstall = toString (args.postInstall or "") + ''
      mkdir -p $out
      ${source.createInfoJson} > $out/.flox.json
    '';
  });
in if args ? project then floxResult else stdenv.mkDerivation args
