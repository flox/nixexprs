{ rustPlatform, floxInternal, flox }:
{ project, overrides ? {}, ... }@args:
let
  projectSource = flox.getSource floxInternal.importingChannelArgs.name project overrides;
in
rustPlatform.buildRustPackage (args // {
  inherit (projectSource) pname version src;
})
