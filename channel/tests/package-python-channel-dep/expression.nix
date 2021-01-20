let channel = import <test> { };
in builtins.mapAttrs (name: value: value.requests.result) channel
