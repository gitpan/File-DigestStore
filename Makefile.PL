use strict;
use inc::Module::Install;

name 'File-DigestStore';
all_from 'lib/File/DigestStore.pm';

requires 'Algorithm::Nhash';
requires 'Digest';
requires 'Path::Class';
requires 'Moose';

recommends 'Digest::SHA';

WriteAll;
