# flox version of beamPackages.buildErlangMk, enhanced to provide
# all the magic required to locate source, version and build number
# from metadata cached by the nixpkgs mechanism.

# Arguments provided to callPackage().
{ lib, beamPackages, buildErlangMk, meta, ... }:

# Arguments provided to flox.mkDerivation()
{ project ? null # the name of the project, required
, channel ? meta.importingChannel, nativeBuildInputs ? [ ], ... }@args:
let
  source = meta.getChannelSource channel project args;
  # Actually create the derivation.
  floxResult = buildErlangMk (removeAttrs args [ "channel" ] // {
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
      ${source.createInfoJson} > $out/.flox.json
    '';
  });
in if args ? project then floxResult else buildErlangMk args
