let value = import <test> { };
in {
  python27Packages = value.python27Packages.testPackage.name;
  python2Packages = value.python2Packages.testPackage.name;
  python310Packages = value.python310Packages.testPackage.name;
  python36Packages = value.python36Packages.testPackage.name;
  python37Packages = value.python37Packages.testPackage.name;
  python38Packages = value.python38Packages.testPackage.name;
  python39Packages = value.python39Packages.testPackage.name;
  python3Packages = value.python3Packages.testPackage.name;
  pythonPackages = value.pythonPackages.testPackage.name;
}
