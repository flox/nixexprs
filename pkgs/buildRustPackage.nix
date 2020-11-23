{ rustPlatform, meta }:
{ project, ... }@args:
rustPlatform.buildRustPackage (args // {
  inherit (meta.getSource project args) pname version src;
})
