builtins.mapAttrs (name: value: value.testPackage.name) (import <test> {})
