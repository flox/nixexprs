# flox version of beamPackages.buildErlangMk, enhanced to provide
# all the magic required to locate source, version and build number
# from metadata cached by the nixpkgs mechanism.

# Arguments provided to callPackage().
{ lib, beamPackages, meta, ... }:

# Arguments provided to flox.mkDerivation()
{ project # the name of the project, required
, nativeBuildInputs ? [ ], ... }@args:
let
  source = meta.getBuilderSource project args;
  # Actually create the derivation.
in beamPackages.buildErlangMk (args // {
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
})
