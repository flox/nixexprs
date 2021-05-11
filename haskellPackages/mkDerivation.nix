{ mkDerivation, lib, meta }:

{ project # the name of the project, required
, ... }@args:

let source = meta.getBuilderSource project args;
in mkDerivation (removeAttrs args [ "project" ] // {
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
