#!/usr/bin/env perl
use warnings;
use strict;

use lib qw( t/lib );

use Test::File::DigestStore;
use Test::File::DigestStore2;
Test::Class->runtests();
