let value = import <root> { };
in {
  rootPackage = value.rootPackage.result;
  testPackage = value.testPackage.result;
}
