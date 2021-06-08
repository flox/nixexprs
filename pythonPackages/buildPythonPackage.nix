# flox version of stdenv.mkDerivation, enhanced to provide all the
# magic required to locate source, version and build number from
# metadata cached by the nixpkgs mechanism.

# Arguments provided to callPackage().
{ python, pythonPackages, buildPythonPackage, lib, meta }:

# Arguments provided to flox.buildPythonPackage()
{ project # the name of the project, required
, channel ? meta.importingChannel, nativeBuildInputs ? [ ], ... }@args:

let source = meta.getChannelSource channel project args;
in builtins.trace (''flox.buildPythonPackage(project="'' + project + ''", ''
  + ''python.version="'' + python.version + ''", '' + "with "
  + builtins.toString (builtins.length (builtins.attrNames pythonPackages))
  + " pythonPackages)")
# Actually create the derivation.
buildPythonPackage (removeAttrs args [ "channel" ] // {
  inherit (source) version src pname;

  # This for one sets meta.position to where the project is defined
  pos = builtins.unsafeGetAttrPos "project" args;

  # Add tools for development environment only.
  nativeBuildInputs = nativeBuildInputs
    ++ [ pythonPackages.ipython pythonPackages.ipdb ];

  # Namespace *.pth files are only processed for paths found within
  # $NIX_PYTHONPATH, so ensure that this variable is defined for all
  # "pre" hooks referenced in setuptools-{build,check}-hook.sh.
  preBuild = toString (args.preBuild or "") + ''
    export NIX_PYTHONPATH=$PYTHONPATH
  '';
  preCheck = toString (args.preCheck or "") + ''
    export NIX_PYTHONPATH=$PYTHONPATH
  '';
  # In the case of shells, we also have to disable PEP517 in the
  # event that users have a pyproject.toml file sitting around.
  preShellHook = toString (args.preShellHook or "") + ''
    export NIX_PYTHONPATH=$PYTHONPATH
    export PIP_USE_PEP517=false
  '';
  # Clean up PEP517 variable after "pip install" is complete.
  postShellHook = toString (args.postShellHook or "") + ''
    unset PIP_USE_PEP517
  '';

  # Create .flox.json file in root of package dir to record
  # details of package inputs.
  postInstall = toString (args.postInstall or "") + ''
    mkdir -p $out
    ${source.createInfoJson} > $out/.flox.json
  '';
})
