let channel = import <test> { };
in {
  dir = channel.dir._floxPath;
  file = channel.file._floxPath;
  pythonDir = channel.pythonPackages.dir._floxPath;
  pythonFile = channel.pythonPackages.file._floxPath;
}
