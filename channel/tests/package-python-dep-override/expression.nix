let channel = import <test> { };
in { black = channel.python3Packages.black.result; }
