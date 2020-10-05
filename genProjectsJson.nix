# Use ./genProjectsJson for evaluating this
{ errorSetJson
, tracePrefix
}:
let
  lib = import <nixpkgs/lib>;

  collectEntries = set: errorSet: attrPath:
    let
      shouldRecurse = lib.isAttrs set && ! lib.isDerivation set && ! set ? project && set.recurseForDerivations or true;

      subResult = map (attr:
        collectEntries set.${attr} (errorSet.${attr} or null) (attrPath ++ [ attr ])
      ) (lib.attrNames set);

  # Generate attrName/projectName tuples for top-level packages
  # containing "project" attribute.
  top_level_mappings = map (x: {
    attrName = x;
    projectName = attributes.${x}.project;
  }) (
    builtins.filter (x: builtins.hasAttr "project" attributes.${x}) (
      builtins.attrNames attributes
    )
  );

  # Function to generate attrName/projectName tuples for packages
  # of a sub-namespace (e.g. "perlPackages", "pythonPackages").
  genMapping = namespace:
    let
      pkglist = builtins.filter (x:
        builtins.hasAttr "project" attributes.${namespace}.${x}
      ) ( builtins.attrNames attributes.${namespace} );
    in
      map (x: {
        attrName = namespace + "." + x;
        projectName = attributes.${namespace}.${x}.project;
      }) pkglist;

      # Outputs the attribute path that's being evaluated to stderr
      # (when --show-trace) with a known format such that we can detect it and
      # filter it out in a next evaluation
      withErrorContext = builtins.addErrorContext "${tracePrefix}${builtins.toJSON attrPath}";

      result =
        if lib.isString errorSet then {}
        else lib.zipAttrsWith (name: lib.concatLists) (lib.optionals shouldRecurse subResult ++ ownResult);
    in withErrorContext result;

in collectEntries (import ./. {}) (lib.importJSON errorSetJson) []
