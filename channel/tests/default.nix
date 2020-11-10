let
  nixpkgs = fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/a52e974cff8fb80c427e0d55c01b3b8c770ccec4.tar.gz";
    sha256 = "0yhcnn435j9wfi1idxr57c990aihg0n8605566f2l8vfdrz7hl7d";
  };
  pkgs = import nixpkgs {
    config = {};
    overlays = [];
  };
  inherit (pkgs) lib;

  createNixPath = entries: lib.concatMapStringsSep ":" ({ prefix, path }:
    if prefix == "" then path
    else prefix + "=" + path
  ) entries;

  testRunner = path:
    let
      config = import (path + "/config.nix");
      nixPath = createNixPath (config.nixPath {
        nixpkgs = nixpkgs;
        flox = ../..;
      });
      args = lib.escapeShellArgs (map (arg: "${arg}") config.args);

      check = file: lib.optionalString (builtins.pathExists (path + "/${file}")) ''
        while read -r line; do
          if ! grep -xF "$line" ${file} >/dev/null; then
            echo "Expected ${file} to contain line"
            echo "$line"
            echo "But it doesn't"
            echo "Test failed"
            fail
          fi
        done < ${path + "/${file}"}
      '';

    in pkgs.runCommandNoCC "nixexprs-test-${baseNameOf path}" {
      nativeBuildInputs = [ pkgs.nix ];
    } ''
      root=$(mktemp -d)
      export NIX_STATE_DIR=$root/var/nix
      export NIX_PATH=${nixPath}

      fail() {
        echo "stdout is"
        cat stdout
        echo "stderr is"
        cat stderr
        exit 1
      }

      echo "NIX_PATH=${nixPath} nix-instantiate ${args}"
      NIX_PATH=${nixPath} nix-instantiate ${args} >stdout 2>stderr
      exitCode=$?
      if [[ "$exitCode" -ne "${toString config.exitCode}" ]]; then
        echo "Expected exit code ${toString config.exitCode} but got $exitCode"
        fail
      fi
      ${check "stdout"}
      ${check "stderr"}
      echo "Test succeeded"
      touch $out
    '';

in {
  trivial = testRunner ./trivial;
}
