# flox version of stdenv.mkDerivation, enhanced to provide all the
# magic required to locate source, version and build number from
# metadata cached by the nixpkgs mechanism.

{ stdenv, getSource, meta }:

# Arguments provided to flox.mkDerivation()
{ project	# the name of the project, required
, ... } @ args:

# Actually create the derivation.
stdenv.mkDerivation ( args // {
  inherit (meta.getSource project args) version src name;
  # Create .flox.json file in root of package dir to record
  # details of package inputs.
  postInstall = toString (args.postInstall or "") + ''
    mkdir -p $out
    echo $src_json > $out/.flox.json
  '';
} )
