{ rustPlatform, meta }:
{ project, ... }@args:
rustPlatform.buildRustPackage (args // {
  inherit (meta.getBuilderSource project args) pname version src src_json;

  # This for one sets meta.position to where the project is defined
  pos = builtins.unsafeGetAttrPos "project" args;

  # Create .flox.json file in root of package dir to record
  # details of package inputs.
  postInstall = toString (args.postInstall or "") + ''
    mkdir -p $out
    echo $src_json > $out/.flox.json
  '';
})
