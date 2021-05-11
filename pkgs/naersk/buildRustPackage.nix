{ fetchFromGitHub, callPackage, lib, meta }:
{ project, ... }@args:
let
  source = meta.getBuilderSource project args;

  naersk = fetchFromGitHub {
    owner = "nmattia";
    repo = "naersk";
    rev = "a76924cbbb17c387e5ae4998a4721d88a3ac95c0";
    sha256 = "09b5g2krf8mfpajgz2bgapkv3dpimg0qx1nfpjafcrsk0fhxmqay";
  };
  naersk-lib = callPackage naersk { };
in naersk-lib.buildPackage (args // {
  inherit (source) pname version src;

  # This for one sets meta.position to where the project is defined
  pos = builtins.unsafeGetAttrPos "project" args;

  # Create .flox.json file in root of package dir to record
  # details of package inputs.
  postInstall = toString (args.postInstall or "") + ''
    mkdir -p $out
    ${source.createInfoJson} > $out/.flox.json
  '';
})
