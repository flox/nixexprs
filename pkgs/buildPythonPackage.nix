# flox version of stdenv.mkDerivation, enhanced to provide all the
# magic required to locate source, version and build number from
# metadata cached by the nixpkgs mechanism.

# Arguments provided to callPackage().
{ nixpkgs, flox }:
let
  inherit (nixpkgs) python pythonPackages;
in 

# Arguments provided to flox.buildPythonPackage()
{ project		# the name of the project, required
, nativeBuildInputs ? []
, ... } @ args:

builtins.trace (
  "flox.buildPythonPackage(project=\"" + project + "\", " +
  "python.version=\"" + python.version + "\", " +
  "with " + builtins.toString ( builtins.length (
    builtins.attrNames pythonPackages)) + " pythonPackages)"
)

# Actually create the derivation.
nixpkgs.pythonPackages.buildPythonPackage ( args // {
  inherit (flox.setSourceVersion project args) version src pname src_json;
  # Add tools for development environment only.
  nativeBuildInputs = nativeBuildInputs ++ [
    pythonPackages.ipython
    pythonPackages.ipdb
  ];

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
    echo $src_json > $out/.flox.json
  '';
} )
