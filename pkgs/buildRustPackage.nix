{ rustPlatform, lib, meta }:
{ project, ... }@args:
let source = meta.getBuilderSource project args;
in rustPlatform.buildRustPackage (args // rec {
  inherit (source) pname version src;

  # Ensure that the cargoDeps path and checksum don't change with
  # the change of `name` that occurs with version changes.
  # - https://github.com/NixOS/nixpkgs/issues/112763
  # - https://github.com/NixOS/nixpkgs/pull/113176
  cargoDepsName = pname;

  # This for one sets meta.position to where the project is defined
  pos = builtins.unsafeGetAttrPos "project" args;

  # Create .flox.json file in root of package dir to record
  # details of package inputs.
  postInstall = toString (args.postInstall or "") + ''
    mkdir -p $out
    ${source.createInfoJson} > $out/.flox.json
  '';
})
