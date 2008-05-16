#!/usr/bin/env perl
use warnings;
use strict;

use Test::More;

plan tests => 9;

use File::Temp qw( :POSIX );

use File::DigestStore;

my $tmp = tmpnam();

my($store, $id, $id2);

eval {
  $store = new File::DigestStore;
};
like($@, qr/^Attribute \(root\) is required /, "ensure root is not optional");

$store = new File::DigestStore root => $tmp;

$id = $store->store_file($0);
$id2 =  $store->store_file($0);

is($id, $id2, 'Hash is stable and returns same ID');

ok($store->exists($id), 'exists() returns true for valid ID');
$id++;
ok(!$store->exists($id), 'exists() returns false for invalid ID');

eval {
  $id = $store->store_file("$tmp/this/is/an/invalid/filename");
};
like($@, qr/^Can't read /, "fails on unreadable file");

foreach my $string ('', 'Hello, world') {
  $id = $store->store_string($string);
  $id2 = $store->store_string($string);
  is($id, $id2, 'Hash is stable and returns same ID');
  my $string2 = $store->fetch_string($id);
  is($string, $string2, 'Returned string is correct');
}

system (rm => -rf => $tmp);
