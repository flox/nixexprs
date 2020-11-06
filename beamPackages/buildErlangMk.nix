# flox version of beamPackages.buildErlangMk, enhanced to provide
# all the magic required to locate source, version and build number
# from metadata cached by the nixpkgs mechanism.

# Arguments provided to callPackage().
{ beam, erlangR18, getSource, floxInternal, ... }:

# Arguments provided to flox.mkDerivation()
{ project	# the name of the project, required
, erlang ? erlangR18
, beamPackages ? beam.packages.erlangR18
, nativeBuildInputs ? []
, ... } @ args:

# Actually create the derivation.
beamPackages.buildErlangMk ( args // rec {
  # build-erlang-mk.nix re-appends the version to the name,
  # so we need to not inherit name and instead pass what we
  # call "pname" as "name".
  inherit (getSource floxInternal.importingChannelArgs.name project args) version src pname src_json;
  name = pname;

  # Create .flox.json file in root of package dir to record
  # details of package inputs.
  postInstall = toString (args.postInstall or "") + ''
    mkdir -p $out
    echo $src_json > $out/.flox.json
  '';
} )
