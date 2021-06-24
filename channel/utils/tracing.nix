{ lib ? import <nixpkgs/lib> }:

let

  showValue = value:
    if lib.isList value then lib.concatMapStringsSep " " showValue value
    else if lib.strings.isCoercibleToString value then toString value
    else lib.generators.toPretty { multiline = false; } value;

  traceWith = { defaultVerbosity, subsystemVerbosities }:
    let
      trace = context: {

        inherit showValue;

        _contextPrefix = lib.concatMapStrings (c:
          "[${c.name}${lib.optionalString (c.name != "") "="}${showValue c.value}] "
        ) context;

        context = name: value: trace (context ++ [ { inherit name value; } ]);

        __functor = self: subsystem: verbosity:
          if subsystemVerbosities.${subsystem} or defaultVerbosity >= verbosity
          then message: builtins.trace "<${subsystem}:${toString verbosity}> ${self._contextPrefix}${showValue message}"
          else message: value: value;

      };
    in trace [];

  example =
    let
      mainTrace = traceWith {
        defaultVerbosity = 0;
        subsystemVerbosities.sum = 3;
      };

      values = {
        foo = 2;
        baz = 3;
      };

      input = [ "foo" null "bar" "foo" "baz" ];

      sum = trace: values: lib.foldl' (acc: el:
        trace "sum" 3 "Increasing accumulator ${toString acc} by ${toString el}" (acc + el)
      ) 0 values;

      getValue = trace: attr: values.${attr} or (trace "getValue" 0 "Attribute ${attr} doesn't exist, assuming value of 0" 0);

      attrFilter = trace: attr: if attr == null then trace "filter" 0 "Attribute is null, ignoring" false else true;

      result = trace: sum trace (map (el: getValue (trace.context "index" el.n) el.value) (lib.filter (el: attrFilter (trace.context "index" el.n) el.value) (lib.imap0 (n: value: { inherit n value; }) input)));

    in result mainTrace;

in {
  inherit traceWith example;
}
