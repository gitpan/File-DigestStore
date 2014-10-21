package Test::File::DigestStore2;
use base qw/ Test::Class /;
use warnings;
use strict;

use Test::More;
use Test::Exception;

use File::Temp qw/ :POSIX /;
use File::stat;

use File::DigestStore;

sub setup : Test(setup) {
    my($self) = @_;

    $self->{tmp} = tmpnam;
}

sub teardown : Test(teardown) {
    my($self) = @_;

    my $store = $self->{store};
    return unless $store;
    system (rm => -rf => $store->root)
      if defined $store->root;
    delete $self->{store};
}

sub ctor_requires_root : Test(no_plan) {
    my($self) = @_;

    throws_ok( sub { $self->{store} = File::DigestStore->new },
               qr/^Attribute \(root\) is required /,
               'ensure root is not optional' );
};

sub ctor_requires_levels : Test(no_plan) {
    my($self) = @_;

    my $store = $self->{store}
      = File::DigestStore->new( root => $self->{tmp},
                                levels => '' );
    # FIXME: new() should throw instead
    throws_ok( sub { $store->nhash },
               qr/^At least one storage level is required /,
               'check for empty storage levels' );
};

# we're mostly doing tests for the octal_mode type because Moose
# occasionally fights back and breaks the coercion code. This tests that the
# coercions are working.

sub octal1 : Test(no_plan) {
    my($self) = @_;

    my $store = $self->{store}
      = File::DigestStore->new(root => $self->{tmp},
                               dir_mask => 0750,
                               file_mask => 0640
                              );

    is($store->dir_mask, 0750, 'dir_mask');
    is($store->file_mask, 0640, 'file_mask');
}

sub octal2 : Test(no_plan) {
    my($self) = @_;

    my $store = $self->{store}
      = File::DigestStore->new(root => $self->{tmp},
                               dir_mask => '0750',
                               file_mask => '0640'
                              );

    is($store->dir_mask, 0750, 'dir_mask');
    is($store->file_mask, 0640, 'file_mask');
}

sub mask {
    my($self, $umask, $dirperm, $fileperm) = @_;

    my $oldmask = umask $umask;

    my $store = $self->{store}
      = File::DigestStore->new(root => $self->{tmp},
                               dir_mask => 0750,
                               file_mask => 0640
                              );

    # store test data and obtain its path
    my $id = $store->store_string('test');
    my $path = $store->fetch_path($id);

    is(stat($self->{tmp})->mode & 0777, $dirperm, 'dir perms');
    is(stat($path)->mode & 0777, $fileperm, 'file perms');

    umask $oldmask;
}

sub mask1 : Test(no_plan) {
    my($self) = @_;

    $self->mask(0, 0750, 0640);
}

sub mask2 : Test(no_plan) {
    my($self) = @_;

    $self->mask(0077, 0700, 0600);
}

1;
