# flox version of stdenv.mkDerivation, enhanced to provide all the
# magic required to locate source, version and build number from
# metadata cached by the nixpkgs mechanism.

# Arguments provided to callPackage().
{ buildPerlPackage, lib, meta }:

# Arguments provided to flox.mkDerivation()
{ project	# the name of the project, required
, ... } @ args:
let
  source = meta.getBuilderSource project args;
in
# Actually create the derivation.
buildPerlPackage ( args // {
  inherit (source) version src pname;

  # This for one sets meta.position to where the project is defined
  pos = builtins.unsafeGetAttrPos "project" args;

  # Create .flox.json file in root of package dir to record
  # details of package inputs.
  postInstall = toString (args.postInstall or "") + ''
    mkdir -p $out
    echo ${lib.escapeShellArg source.infoJson} > $out/.flox.json
  '';
} )
