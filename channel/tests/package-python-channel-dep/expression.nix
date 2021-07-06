let
  value = import <test> {};
in
{
  python27Packages = value.python27Packages.requests.result;
  python2Packages = value.python2Packages.requests.result;
  python310Packages = value.python310Packages.requests.result;
  python36Packages = value.python36Packages.requests.result;
  python37Packages = value.python37Packages.requests.result;
  python38Packages = value.python38Packages.requests.result;
  python39Packages = value.python39Packages.requests.result;
  python3Packages = value.python3Packages.requests.result;
  pythonPackages = value.pythonPackages.requests.result;
}
