{ mkDerivation, lib, meta }:

{ project ? null # the name of the project, required
, channel ? meta.importingChannel, ... }@args:
if !args ? project then
  mkDerivation args
else

  let source = meta.getChannelSource channel project args;
  in mkDerivation (removeAttrs args [ "project" "channel" ] // {
    inherit (source) pname version src;

    # We can't set the position because mkDerivation doesn't pass on extra attributes to stdenv.mkDerivation
    # pos = builtins.unsafeGetAttrPos "project" args;

    # Create .flox.json file in root of package dir to record
    # details of package inputs.
    postInstall = toString (args.postInstall or "") + ''
      mkdir -p $out
      ${source.createInfoJson} > $out/.flox.json
    '';

    passthru = { inherit project; } // args.passthru or { };
    license = args.license or null;
  })
