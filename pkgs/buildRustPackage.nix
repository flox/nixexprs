{ rustPlatform, lib, meta }:
{ project, ... }@args:
let
  source = meta.getBuilderSource project args;
in
rustPlatform.buildRustPackage (args // {
  inherit (source) pname version src;

  # This for one sets meta.position to where the project is defined
  pos = builtins.unsafeGetAttrPos "project" args;

  # Create .flox.json file in root of package dir to record
  # details of package inputs.
  postInstall = toString (args.postInstall or "") + ''
    mkdir -p $out
    echo ${lib.escapeShellArg source.infoJson} > $out/.flox.json
  '';
})
