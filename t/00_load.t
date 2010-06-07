#!perl -T
## no critic (RequireUseStrict)

use Test::More tests => 1;

BEGIN {
    use_ok( 'File::DigestStore' );
}

diag( "Testing File::DigestStore $File::DigestStore::VERSION, Perl $], $^X" );
