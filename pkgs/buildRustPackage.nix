{ rustPlatform, meta }:
{ project, ... }@args:
rustPlatform.buildRustPackage (args // {
  inherit (meta.getBuilderSource project args) pname version src src_json;

  # Create .flox.json file in root of package dir to record
  # details of package inputs.
  postInstall = toString (args.postInstall or "") + ''
    mkdir -p $out
    echo $src_json > $out/.flox.json
  '';
})
