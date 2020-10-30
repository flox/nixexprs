# flox version of stdenv.mkDerivation, enhanced to provide all the
# magic required to locate source, version and build number from
# metadata cached by the nixpkgs mechanism.

{ nixpkgs, flox }:

# Arguments provided to flox.mkDerivation()
{ project	# the name of the project, required
, ... } @ args:

# Actually create the derivation.
nixpkgs.stdenv.mkDerivation ( args // {
  inherit (flox.setSourceVersion project args) version src name;
  # Create .flox.json file in root of package dir to record
  # details of package inputs.
  postInstall = toString (args.postInstall or "") + ''
    mkdir -p $out
    echo $src_json > $out/.flox.json
  '';
} )
