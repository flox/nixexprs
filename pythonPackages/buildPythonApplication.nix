# flox version of stdenv.mkDerivation, enhanced to provide all the
# magic required to locate source, version and build number from
# metadata cached by the nixpkgs mechanism.

# Arguments provided to callPackage().
{ python, pythonPackages, lib, meta }:

# Arguments provided to flox.mkDerivation()
{ project	# the name of the project, required
, nativeBuildInputs ? []
, ... } @ args:
let
  source = meta.getBuilderSource project args;
in
builtins.trace (
  "flox.buildPythonApplication(project=\"" + project + "\", " +
  "python.version=\"" + python.version + "\", " +
  "with " + builtins.toString ( builtins.length (
    builtins.attrNames pythonPackages)) + " pythonPackages)"
)

# Actually create the derivation.
pythonPackages.buildPythonApplication ( args // {
  inherit (source) version src pname;

  # This for one sets meta.position to where the project is defined
  pos = builtins.unsafeGetAttrPos "project" args;

  # Add tools for development environment only.
  nativeBuildInputs = nativeBuildInputs ++ [
    pythonPackages.ipython
    pythonPackages.ipdb
  ];
  makeWrapperArgs = (args.makeWrapperArgs or []) ++ [
    "--set" "NIX_SELF_PATH" "$out"
    "--run 'export NIX_ORIG_ARGV0=\$0'"
  ];
  # Create .flox.json file in root of package dir to record
  # details of package inputs.
  postInstall = toString (args.postInstall or "") + ''
    mkdir -p $out
    echo ${lib.escapeShellArg source.infoJson} > $out/.flox.json
  '';

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

  # We don't like the way that the wrapper wraps python applications
  # because it perturbs the environment of child processes. While it
  # would be possible to replace the Nix default wrapPython with one
  # of our own invention, it's more expedient to just post-process
  # what Nix has provided, and this may well serve us in good stead
  # as the default Nix wrapper continues to evolve over time.
  #
  # Define the floxUnwrapPython array to use this feature, e.g.
  #   floxUnwrapPython = [
  #     "bin/*"
  #     "sbin/foo"
  #   ];
  postFixup = (args.postFixup or "") + ''
    # Start subshell so we can cd.
    (
      cd $out
      for i in $floxUnwrapPython; do
        # Defeat PATH and PYTHONNOUSERSITE wrapping
        sed -i $i \
          -e 's/^export PATH=/export _NIX_WRAPPED_PATH=/' \
          -e '/^export PYTHONNOUSERSITE=/d'
        # Add the "-s" flag to the (wrapped) python invocation to
        # accomplish the same thing as PYTHONNOUSERSITE variable.
        _wrapped=".$(basename $i)-wrapped"
        _dirname=$(dirname $i)
        sed -i $_dirname/$_wrapped \
          -e '1 s^\(#!.*/nix/store/.*python.*\)^\1 -s^'
      done
    )
  '';
} )
