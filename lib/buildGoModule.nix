# flox version of stdenv.mkDerivation, enhanced to provide all the
# magic required to locate source, version and build number from
# metadata cached by the nixpkgs mechanism.

# Arguments provided to callPackage().
{ buildGoModule, floxSetSrcVersion, ... }:

# Arguments provided to flox.mkDerivation()
{ project	# the name of the project, required
, ... } @ args:

# Actually create the derivation.
buildGoModule ( args // rec {
  inherit (floxSetSrcVersion project args) version autoversion src name src_json;

  # Go development in Nix at flox follows the convention of injecting the
  # version string at build time using ldflags. Nix will deduce the version for
  # you, or you can provide an override version in your nix expression. Requires
  # "var version string" in your application.

  buildFlagsArray = (args.buildFlagsArray or []) ++ [
    "-ldflags=-X main.nixVersion=${autoversion}"
  ];
  # Create .flox.json file in root of package dir to record
  # details of package inputs.
  postInstall = toString (args.postInstall or "") + ''
    mkdir -p $out
    echo $src_json > $out/.flox.json
  '';
} )
