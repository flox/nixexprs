{ mkDerivation, getSource, floxInternal }:

{ project	# the name of the project, required
, ... } @ args:

mkDerivation (removeAttrs args [ "project" ] // {
  inherit (getSource floxInternal.importingChannelArgs.name project args) pname version src;
  passthru = { inherit project; } // args.passthru or {};
  license = args.license or null;
})