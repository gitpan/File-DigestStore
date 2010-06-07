#!perl -T

use strict;
use warnings;
use Test::More;

eval "use Test::CheckManifest 0.9";
plan skip_all => "Test::CheckManifest 0.9 required" if $@;
plan skip_all => "set TEST_RELEASE to enable this author test"
  unless $ENV{TEST_RELEASE};
ok_manifest();
