{ rustPlatform, meta }:
{ project, ... }@args:
rustPlatform.buildRustPackage (args // {
  inherit (meta.getBuilderSource project args) pname version src;
})
