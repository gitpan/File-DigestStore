# -*- mode: cperl; -*-
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new
  (
   module_name => 'File::DigestStore',
   license => 'perl',
   dist_author => q{Peter Corlett <abuse@cabal.org.uk>},
   dist_version_from => 'lib/File/DigestStore.pm',
   build_requires =>
   {
    'Test::More' => 0,
    'Test::Class' => 0,
    'Test::Exception' => 0,
    'Readonly' => 0,
    # test requires these, the module doesn't strictly need them but the
    # default configuration does.
    'Digest::SHA' => 0,
    'Algorithm::Nhash' => 0,
   },
   requires =>
   {
    'Moose' => 0,
    'MooseX::Types::Moose' => 0,
    'MooseX::Types::Path::Class' => 0,
    'namespace::clean' => 0,
   },

   recommends =>
   {
    # for extra testing
    'Test::Pod' => 1.22,
    'Test::CheckManifest' => 0.9,
    'Test::Pod::Coverage' => 1.08,
    'Pod::Coverage' => 0.18,
   },

   add_to_cleanup => [ 'File-DigestStore-*' ],
   create_makefile_pl => 'traditional',
   create_readme => 1,
  );

$builder->create_build_script();
