{ hello }: hello.overrideAttrs (old: { name = "my-${old.pname}"; })
