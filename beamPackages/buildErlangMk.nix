# flox version of beamPackages.buildErlangMk, enhanced to provide
# all the magic required to locate source, version and build number
# from metadata cached by the nixpkgs mechanism.

# Arguments provided to callPackage().
{ lib, beam, erlangR18, meta, ... }:

# Arguments provided to flox.mkDerivation()
{ project	# the name of the project, required
, erlang ? erlangR18
, beamPackages ? beam.packages.erlangR18
, nativeBuildInputs ? []
, ... } @ args:
let
  source = meta.getBuilderSource project args;
in
# Actually create the derivation.
beamPackages.buildErlangMk ( args // {
  # build-erlang-mk.nix re-appends the version to the name,
  # so we need to not inherit name and instead pass what we
  # call "pname" as "name".
  inherit (source) version src pname;
  name = source.pname;

  # This for one sets meta.position to where the project is defined
  pos = builtins.unsafeGetAttrPos "project" args;

  # Create .flox.json file in root of package dir to record
  # details of package inputs.
  postInstall = toString (args.postInstall or "") + ''
    mkdir -p $out
    echo ${lib.escapeShellArg source.infoJson} > $out/.flox.json
  '';
} )
