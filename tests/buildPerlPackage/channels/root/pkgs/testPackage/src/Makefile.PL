use inc::Module::Install;

name 'Hello';
all_from 'Hello.pm';
install_script 'hello';
auto_install;
WriteAll;
