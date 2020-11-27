# flox version of stdenv.mkDerivation, enhanced to provide all the
# magic required to locate source, version and build number from
# metadata cached by the nixpkgs mechanism.

# Arguments provided to callPackage().
{ buildGoPackage, lib, meta, ... }:

# Arguments provided to flox.mkDerivation()
{ project	# the name of the project, required
, ... } @ args:
let
  source = meta.getBuilderSource project args;
in
# Actually create the derivation.
buildGoPackage ( args // rec {
  inherit (source) version src name;

  # This for one sets meta.position to where the project is defined
  pos = builtins.unsafeGetAttrPos "project" args;

  # Go development in Nix at flox follows the convention of injecting the
  # version string at build time using ldflags. Nix will deduce the version for
  # you, or you can provide an override version in your nix expression. Requires
  # "var nixVersion string" in your application.

  buildFlagsArray = (args.buildFlagsArray or []) ++ [
    "-ldflags=-X main.nixVersion=${source.version}"
  ];
  # Create .flox.json file in root of package dir to record
  # details of package inputs.
  postInstall = toString (args.postInstall or "") + ''
    mkdir -p $out
    echo ${lib.escapeShellArg source.infoJson} > $out/.flox.json
  '';
} )
