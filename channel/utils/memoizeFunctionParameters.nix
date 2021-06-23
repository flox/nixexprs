{ lib ? import <nixpkgs/lib> }: rec {
  /*
  Memoizes a function taking an attribute set of strings over a parameter space

  memoizeFunctionParameters :: AttrsOf (ListOf String) -> (AttrsOf String -> Any) -> (AttrsOf String -> Any)

  Example:

    nix-repl> function = { letter, number }: builtins.trace "Evaluating ${letter}${number}" null

    nix-repl> function { letter = "a"; number = "1"; }
    trace: Evaluating a1
    null

    nix-repl> function { letter = "a"; number = "1"; }
    trace: Evaluating a1
    null

    nix-repl> memoizedFunction = memoizeFunctionParameters { letter = [ "a" "b" ]; number = [ "1" "2" ]; } function

    nix-repl> memoizedFunction { letter = "a"; number = "1"; }
    trace: Evaluating a1
    null

    nix-repl> memoizedFunction { letter = "a"; number = "1"; }
    null
  */
  memoizeFunctionParameters = paramSpace: function:
    let
      params = lib.attrNames paramSpace;
      count = lib.length params;

      # Creates a lookup table for all supported values of the next parameter
      # - args is the already-filled out arguments
      # - index is the index of the next parameter
      paramTable = args: index:
        let
          # Look up the name of this index's parameter
          paramName = lib.elemAt params index;
          # Creates an attribute set for each parameter value, recursively
          # calling paramTable for each element with the new value filled out
          table = lib.genAttrs paramSpace.${paramName} (paramValue:
            paramTable (args // { ${paramName} = paramValue; }) (index + 1)
          );
        in
          # If all parameters are filled out, apply the function to them
          if index == count then builtins.trace "memoizeFunctionParameters: Calling function with arguments ${lib.generators.toPretty { multiline = false; } args}" (function args)
          # Only if that's not the case, return the table
          else table;

      # A recursive attribute set for caching the result of the function call
      # for all support parameters. Of the form
      # {
      #   <param1-value>.<param2-value>...<paramk-value> = function {
      #     <param1> = <param1-value>;
      #     <param2> = <param2-value>;
      #     ...
      #     <paramk> = <paramk-value>;
      #   };
      # }
      fullTable = paramTable {} 0;

    in args:
      if lib.attrNames args != params then
        throw "Provided arguments [ ${lib.concatStringsSep ", " (lib.attrNames args)} ] don't match memoized parameters [ ${lib.concatStringsSep ", " params} ]"
      else lib.foldl' (table: argName:
        let argValue = args.${argName}; in
        table.${argValue} or (throw "memoizeFunctionParameters: Parameter \"${argName}\" was not declared to memoize value \"${argValue}\". Only values [ ${lib.concatMapStringsSep ", " (x: "\"${x}\"") (lib.attrNames table)} ] are memoized")
      ) fullTable (lib.attrNames args);

  test = let
    function = { letter, number }: builtins.trace "Evaluating ${letter}${number}" null;
    memoizedFunction = memoizeFunctionParameters { letter = [ "a" "b" ]; number = [ "1" "2" ]; } function;
  in [
    (memoizedFunction { letter = "a"; number = "1"; })
    (memoizedFunction { letter = "a"; number = "1"; })
  ];
}
