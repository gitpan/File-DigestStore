use strict;
use inc::Module::Install;

name 'File-DigestStore';
all_from 'lib/File/DigestStore.pm';

requires 'Algorithm::Nhash';

WriteAll;
