package File::DigestStore;

use vars qw( $VERSION );
$VERSION = '1.005';

use Algorithm::Nhash;
use Carp;
use Digest;
use MooseX::Types -declare => [qw/ OctalMode /];
use MooseX::Types::Moose qw/ Int Str Value /;
use MooseX::Types::Path::Class;
use Moose::Util::TypeConstraints;
use Moose;
use Path::Class qw/ dir file /;
use IO::File;
use Sys::Hostname;
my $hostname = hostname;

subtype OctalMode, as Int, where { not /^0/ };
coerce OctalMode, from Str, via { oct $_ };

has 'root'      => (is => 'ro', isa => 'Path::Class::Dir',
                    coerce => 1, required => 1);
has 'levels'    => (is => 'ro', isa => Str, default => '8,256');
has 'algorithm' => (is => 'ro', isa => Str, default => 'SHA-512');
has 'dir_mask'  => (is => 'ro', isa => OctalMode,
                    coerce => 1, default => 0777);
has 'file_mask' => (is => 'ro', isa => OctalMode,
                    coerce => 1, default => 0666);
has 'layers'    => ( is => 'ro', isa => Str, default => ':raw' );

# private attribute
has 'nhash' => ( is => 'ro', isa => 'Algorithm::Nhash', lazy_build => 1 );

=head1 NAME

File::DigestStore - Digested hierarchical storage of files

=head1 SYNOPSIS

 my $store = File::DigestStore->new( root => '/var/lib/digeststore' );

 # stores the file and returns a short-ish ID
 my $id = $store->store_file('/etc/motd');
 # Will output a hex string like '110fe...'
 print "$id\n";
 # returns a filename that has the same contents as the stored file
 my $path = $store->fetch_file($id);
 # Will return something like '/var/lib/digeststore/1/2/110fe...'
 print "$path\n";

=head1 DESCRIPTION

This module is used to take large files (or strings) and store them on disk
with a name based on the hashed file contents, returning said hash. This
hash is much shorter than the data and is much more easily stored in a
database than the original file. Because of the hashing, only a single copy
of the data will be stored on disk no matter how many times one calls
store_file() or store_string().

=head1 BACKEND STORAGE

The backend data store should be considered opaque as far as your Perl
program is concerned, but it actually consists of the files hashed and then
stored in a multi-level directory structure for fast access. Files are never
moved around the tree so if the stash is particularly large, you can place
subtrees on their own filesystem if required. Directories are created
on-demand and so do not need to be pre-created.

The file's name is just the hash of the file's contents, and the file's
directory is the result of applying the nhash algorithm to the hash. Thus,
replacing the nhash object with another class that provides a nhash() method
allows you to fine-tune the directory layout.

=head1 MOOSE FIELDS

=head2 root (required)

The base directory that is used to store the files. This will be created if
it does not exist, and the stashed files stored underneath it.

=head2 levels (optional, default "8,256")

The number of directory entries in each level of the tree. For example,
"8,256" means that the top-level will have eight directories (called "0"
through "7") and each of those directories will have 256 sub-directories.
The stashed data files appear under those.

=head2 algorithm (optional, default "SHA-512")

The digest algorithm used to hash the files. This is passed to
C<< Digest->new() >>. The file's content is hashed and then stored using that
name, so you should select an algorithm that does not generate collisions.

=head2 dir_mask (optional, default 0777)

The directory creation mask for the stash directories. This is merged with
your umask so the default is usually fine.

As a special case, this will also treat strings starting with a zero as an
octal number. This is helpful when you are using Catalyst::Model::Adaptor on
this class and wish to change the mask in the application configuration
file.

=head2 file_mask (optional, default 0666)

The file creation mask for the stashed files. This is merged with your umask
setting so the default is usually fine.

This has the same special-casing for strings as dir_mask.

=head2 layers (optional, default ":raw")

The PerlIO layer to use when storing and retrieving data.

=head2 nhash (optional, defaults to an Algorithm::Nhash object)

This is the internal Algorithm::Nhash object used to convert a file's hash
into subdirectories. If you're wanting more fine-grained control of the
choice of directory names, you may wish to drop in an alternative object
which provides a nhash() method.

=head1 METHODS

=head2 new

 my $store = File::DigestStore->new( root => '/var/lib/digeststore' );

This creates a handle to a new digested storage area. Arguments are given to
it to define the layout of the storage area. See "MOOSE FIELDS" above for
the available options.

=cut


my $digest2path = sub {
    my($self, $digest) = @_;

    return file($self->root,
                $self->nhash->nhash($digest),
                $digest,
               );
};

my $readfile = sub {
    my($self, $path) = @_;

    my $fh = IO::File->new($path, 'r')
      or croak "Can't read $path: $!";
    $fh->binmode($self->layers);
    local $\;
    # prepending "" covers the case of an empty file, otherwise we'd get undef
    return "".<$fh>;
};

my $writefile = sub {
    my($self, $path, $string) = @_;

    my $unique = file($path->dir, $path->basename.".$hostname.$$");
    my $mode = O_WRONLY | O_CREAT | O_EXCL;
    my $fh = IO::File->new($unique, $mode, $self->{file_mask})
      or die "Can't create $unique: $!";
    $fh->binmode($self->layers);
    print $fh $string;
    $fh->close;

    rename $unique, $path
      or die "Could not rename $unique to $path: $!";
};

=head2 store_file

 my $id = $store->store_file('/etc/motd');

 my ($id, $size) = $store->store_file('/etc/passwd');

This copies the file's contents into the stash. In scalar context it returns
the file's ID. In list context it returns an (ID, file size) tuple. (The
latter saves you having to stat() your file.)

=cut

sub store_file {
    my($self, $path) = @_;

    return $self->store_string($self->$readfile($path));
}

=head2 store_string

 my $id = $store->store_string('Hello, world');

This copies the string's contents into the stash. In scalar context it
returns the file's ID. In list context it returns an (ID, string length)
tuple.

=cut

sub store_string {
    my($self, $string) = @_;

    croak "Can't store an undefined value"
      unless defined $string;

    my $digester = Digest->new($self->algorithm);
    $digester->add($string);
    my $digest = $digester->hexdigest;
    my $path = $self->$digest2path($digest);

    unless(-e $path) {          # skip rewrite if the file already exists
        my $parent = $path->dir;
        $parent->mkpath(0, $self->dir_mask)
          unless -d $parent;

        $self->$writefile($path, $string);
    }
    return wantarray ? ($digest, length $string) : $digest;
}

=head2 fetch_path

 my $path = $store->fetch_path($id);

Given an ID, will return the path to the stashed copy of the file, or undef
if no file with that ID has ever been stored.

Note that the path refers to the master copy of the file within the stash so
you will need to copy the file if you are going to potentially modify it.

=cut

sub fetch_path {
    my($self, $digest) = @_;

    croak "Can't fetch an undefined ID"
      unless defined $digest;

    my $path = $self->$digest2path($digest);
    return unless -f $path;
    return $path;
}

=head2 fetch_string

 my $string = $store->fetch_string($id);

Given an ID, will return the string which was previously stashed to that ID
or undef if no string with that ID has ever been stored.

=cut

sub fetch_string {
    my($self, $digest) = @_;

    my $path = $self->$digest2path($digest);
    return unless -f $path;
    return $self->$readfile($path);
}

=head2 exists

 if($store->exists($id)) {
    # ...
 }

Returns true if anything was stashed with this the given ID, otherwise
false.

=cut

sub exists {
    my($self, $digest) = @_;

    my $path = $self->$digest2path($digest);
    return -f $path;
}

#FIXME
#sub delete {
#  my($self, $digest) = @_;
#
#  die "FIXME";
#}

=head2 DEPRECATED METHODS

=head2 fetch_file

fetch_path was originally called this, but the name is inappropriate since
it implies that it fetches the file and not just the file's name.

=cut

my $fetch_file_called;

sub fetch_file {
    carp "Deprecated fetch_file() called"
      unless $fetch_file_called++;
    goto &fetch_path;
}

sub _build_nhash {
    my($self) = shift;

    my @buckets = split /,/, $self->levels;
    # bail if there are no storage levels; it's not terribly useful and
    # Algorithm::Nhash::nhash() doesn't return an empty path in this case.
    croak "At least one storage level is required"
      unless @buckets;

    return Algorithm::Nhash->new(@buckets);
}

=head1 BUGS

This does not currently check for hash collisions.

You cannot provide a hashing algorithm that is not a Digest::* derivative.

=head1 SEE ALSO

File::HStore implements a similar idea.

=head1 AUTHOR

All code and documentation by Peter Corlett <abuse@cabal.org.uk>.

=head1 COPYRIGHT

Copyright (C) 2008,2010 Peter Corlett <abuse@cabal.org.uk>. All rights
reserved.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SUPPORT / WARRANTY

This is free software. IT COMES WITHOUT WARRANTY OF ANY KIND.

=cut

1;
