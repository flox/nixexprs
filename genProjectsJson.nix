# Use ./genProjectsJson for evaluating this
{ errorSetJson
, tracePrefix
, nixexprsPath
}:
let
  lib = import <nixpkgs/lib>;

  collectEntries = set: errorSet: attrPath:
    let
      shouldRecurse = lib.isAttrs set && ! lib.isDerivation set && ! set ? project && set.recurseForDerivations or true;

      subResult = map (attr:
        collectEntries set.${attr} (errorSet.${attr} or null) (attrPath ++ [ attr ])
      ) (lib.attrNames set);

      ownResult = lib.optional (set ? project) {
        ${set.project} = [ (lib.concatStringsSep "." attrPath) ];
      };

      # Outputs the attribute path that's being evaluated to stderr
      # (when --show-trace) with a known format such that we can detect it and
      # filter it out in a next evaluation
      withErrorContext = builtins.addErrorContext "${tracePrefix}${builtins.toJSON attrPath}";

      result =
        if lib.isString errorSet then {}
        else lib.zipAttrsWith (name: lib.concatLists) (lib.optionals shouldRecurse subResult ++ ownResult);
    in withErrorContext result;

in collectEntries (import nixexprsPath {}) (lib.importJSON errorSetJson) []
