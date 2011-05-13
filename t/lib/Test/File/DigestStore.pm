package Test::File::DigestStore;
use base qw/ Test::Class /;
use warnings;
use strict;

use Test::More;
use Test::Exception;

use File::Temp qw/ :POSIX /;

use File::DigestStore;

sub startup : Test(startup) {
    my($self) = @_;

    $self->{tmp} = tmpnam;
    $self->{store} = File::DigestStore->new( root => $self->{tmp} );
}

sub shutdown : Test(shutdown) {
    my($self) = @_;

    system (rm => -rf => $self->{tmp})
        if defined $self->{tmp};
}

sub stable_file_hash : Test(no_plan) {
    my($self) = @_;
    my $store = $self->{store};

    my $id = $store->store_file($0);
    my $id2 = $store->store_file($0);
    is($id, $id2, 'Hash is stable and returns same ID');
}

sub stable_string_hash : Test(no_plan) {
    my($self) = @_;
    my $store = $self->{store};

    foreach my $string ('', 'Hello, world') {
        # also test scalar store_string
        my $id = $store->store_string($string);
        # also test array store_string
        my($id2, $length) = $store->store_string($string);
        is($id, $id2, 'Hash is stable and returns same ID');
        my $string2 = $store->fetch_string($id);
        is($string2, $string, 'return correct string');
        is($length, length $string, 'return correct length');
    }
}

sub exists_ok : Test(no_plan) {
    my($self) = @_;
    my $store = $self->{store};

    my $id = $store->store_string('');
    ok($store->exists($id), 'exists() returns true for valid ID');
    $id++;
    ok(!$store->exists($id), 'exists() returns false for invalid ID');
}

sub store_missing_file : Test(no_plan) {
    my($self) = @_;
    my $store = $self->{store};
    my $tmp = $self->{tmp};

    throws_ok( sub { $store->store_file("$tmp/this/is/an/invalid/filename") },
               qr/No such file or directory/,
               "fails on unreadable file" );
}

sub fetch_undef : Test(no_plan) {
    my($self) = @_;
    my $store = $self->{store};

    throws_ok( sub { $store->fetch_path },
               qr/Can't fetch an undefined ID/,
               "fetch_path undef" );
}

sub store_undef : Test(no_plan) {
    my($self) = @_;
    my $store = $self->{store};

    throws_ok( sub { $store->store_string },
               qr/^Can't store an undefined value/,
               "fails on store undef" );
}

sub fetch_nonexist : Test(no_plan) {
    my($self) = @_;
    my $store = $self->{store};

    is($store->fetch_path('this ID does not exist'), undef , 'fetch nonexistent');
}

sub warn_fetch_file : Test(no_plan) {
    my($self) = @_;
    my $store = $self->{store};

    my $warn_count = 0;
    local $SIG{__WARN__} = sub {
        my($warning) = @_;
        if ($warning =~ /^Deprecated fetch_file\(\) called/) {
            $warn_count++;
        } else {
            die "unexpected warning $warning";
        }
    };
    my $id = $store->store_string('fetch_file');
    $store->fetch_file($id);
    is($warn_count, 1, 'warned on first use');
    $store->fetch_file($id);
    is($warn_count, 1, 'did not re-warn');
}

# FIXME: check permissions

1;
