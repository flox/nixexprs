{ rustPlatform, meta }:
{ project, overrides ? {}, ... }@args:
rustPlatform.buildRustPackage (args // {
  inherit (meta.getSource project overrides) pname version src;
})
