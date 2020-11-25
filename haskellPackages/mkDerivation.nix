{ mkDerivation, lib, meta }:

{ project	# the name of the project, required
, ... } @ args:

let
  source = meta.getBuilderSource project args;
in
mkDerivation (removeAttrs args [ "project" ] // {
  inherit (source) pname version src;

  # Create .flox.json file in root of package dir to record
  # details of package inputs.
  postInstall = toString (args.postInstall or "") + ''
    mkdir -p $out
    echo ${lib.escapeShellArg source.src_json} > $out/.flox.json
  '';

  passthru = { inherit project; } // args.passthru or {};
  license = args.license or null;
})
