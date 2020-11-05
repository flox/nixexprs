# flox version of stdenv.mkDerivation, enhanced to provide all the
# magic required to locate source, version and build number from
# metadata cached by the nixpkgs mechanism.

# Arguments provided to callPackage().
{ buildPerlPackage, getSource, floxInternal }:

# Arguments provided to flox.mkDerivation()
{ project	# the name of the project, required
, ... } @ args:

# Actually create the derivation.
buildPerlPackage ( args // {
  inherit (getSource floxInternal.parentChannel project args) version src pname src_json;
  # Create .flox.json file in root of package dir to record
  # details of package inputs.
  postInstall = toString (args.postInstall or "") + ''
    mkdir -p $out
    echo $src_json > $out/.flox.json
  '';
} )
