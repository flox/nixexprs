let
  lib = import <nixpkgs/lib>;
  utils = import <flox/channel/utils> { inherit lib; };
  trace = utils.traceWith {
    defaultVerbosity = 0;
    subsystemVerbosities.baz = 1;
    subsystemVerbosities.foo = 2;
  };

  result = lib.genAttrs [ "bar" "baz" "foo" ] (name:
    trace.withContext "name" name (trace:
      lib.genList (number:
        trace.withContext "number" number (trace:
          let
            shouldEval = name == "bar" && number <= 0 || name == "baz" && number
              <= 1 || name == "foo" && number <= 2;
            aValue.${name} = number;
            withEmptyContext = trace.setContext "empty-context" "";
            message = if shouldEval then
              "Previous prefix ${trace.contextPrefix}and value is ${
                trace.showValue aValue
              }"
            else
              throw "This shouldn't be evaluated!";
            result =
              withEmptyContext name number message "${name}-${toString number}";
          in result)) 3));
in result
