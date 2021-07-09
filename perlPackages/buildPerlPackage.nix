# flox version of stdenv.mkDerivation, enhanced to provide all the
# magic required to locate source, version and build number from
# metadata cached by the nixpkgs mechanism.

# Arguments provided to callPackage().
{ buildPerlPackage, lib, meta }:

# Arguments provided to flox.mkDerivation()
{ project ? null # the name of the project, required
, channel ? meta.importingChannel, ... }@args:
if !args ? project then
  buildPerlPackage args
else
  let
    source = meta.getChannelSource channel project args;
    # Actually create the derivation.
  in buildPerlPackage (removeAttrs args [ "channel" ] // {
    inherit (source) version src pname;

    # This for one sets meta.position to where the project is defined
    pos = builtins.unsafeGetAttrPos "project" args;

    # Create .flox.json file in root of package dir to record
    # details of package inputs.
    postInstall = toString (args.postInstall or "") + ''
      mkdir -p $out
      ${source.createInfoJson} > $out/.flox.json
    '';
  })
