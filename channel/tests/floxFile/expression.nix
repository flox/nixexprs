let channel = import <test> { };
in {
  dir = channel.dir._floxFile;
  file = channel.file._floxFile;
  pythonDir = channel.pythonPackages.dir._floxFile;
  pythonFile = channel.pythonPackages.file._floxFile;
}
