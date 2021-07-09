{ lib ? import <nixpkgs/lib> }:

let

  showValue = value:
    if lib.isString value then
      value
    else
      lib.generators.toPretty { multiline = false; } value;

  traceWith = { defaultVerbosity ? 0, subsystemVerbosities ? { } }:
    let
      trace = context: {

        inherit showValue;

        contextPrefix = lib.concatMapStrings (c:
          "[${c.name}${lib.optionalString (c.name != "") "="}${
            showValue c.value
          }] ") context;

        setContext = name: value: trace (context ++ [{ inherit name value; }]);

        withContext = name: value: cont:
          cont (trace (context ++ [{ inherit name value; }]));

        __functor = self: subsystem: verbosity:
          if subsystemVerbosities.${subsystem} or defaultVerbosity
          >= verbosity then
            message:
            builtins.trace
            "<${subsystem}:${toString verbosity}> ${self.contextPrefix}${
              showValue message
            }"
          else
            message: value: value;

      };
    in trace [ ];

in { inherit traceWith; }
