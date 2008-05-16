package File::DigestStore;

use vars qw( $VERSION );
$VERSION = '1.002';

use Moose;
use Moose::Util::TypeConstraints;

use Carp;

use Path::Class qw/ dir file /;

use IO::File;

use Algorithm::Nhash;
use Digest;

use Sys::Hostname;
my $hostname = hostname;



subtype 'octal_mode'
  => as 'Int';
coerce 'octal_mode'
  => from 'Str' => via { /^0/ ? oct $_ : $_ };

subtype 'Path::Class::Dir'
  => as 'Object';
coerce 'Path::Class::Dir'
  => from 'Str' => via { dir $_ };

# FIXME: remember to test octal coercion actually works

has 'root' => (is => 'ro', isa => 'Path::Class::Dir', coerce => 1, required => 1);
has 'levels' => (is => 'ro', default => '8,256');
has 'algorithm' => (is => 'ro', default => 'SHA-512');
has 'dir_mask' => (is => 'ro', isa => 'octal_mode', coerce => 1, default => 0777);
has 'file_mask' => (is => 'ro', isa => 'octal_mode', coerce => 1, default => 0666);
has '_nhash' => (is => 'rw');

=head1 NAME

File::DigestStore - Digested hierarchical storage of files

=head1 SYNOPSIS

 my $store = new File::DigestStore root => '/var/lib/digeststore';

 # stores the file and returns a short-ish ID
 my $id = $store->store_file('/etc/motd');
 # Will output a hex string like '110fe...'
 print "$id\n";
 # returns a filename that has the same contents as the stored file
 my $path = $store->fetch_file($id);
 # Will return something like '/var/lib/digeststore/1/2/110fe...'
 print "$path\n";

=head1 DESCRIPTION

This module is used to take large files (or strings) and stash them away in
a backend data store, returning a short key that may then be stored in a
database. This avoids having to store large BLOBs in your database.

The backend data store should be considered opaque as far as your Perl
program is concerned, but it actually consists of the files hashed and then
stored in a multi-level directory structure for fast access. Files are never
moved around the tree so if the stash is particularly large, you can place
subtrees on their own filesystem if required. Directories are created
on-demand and so do not need to be pre-created.

=head1 FUNCTIONS

=over 4

=item B<new>

 my $store = new File::DigestStore root => '/var/lib/digeststore';

This creates a handle to a new digested storage area. Arguments are given to
it to define the layout of the storage area:

=over 4

=item B<root> (required)

The base directory that is used to store the files. This will be created if
it does not exist, and the stashed files stored underneath it.

=item B<levels> (optional, default "8,256")

The number of directory entries in each level of the tree. For example,
"8,256" means that the top-level will have eight directories (called "0"
through "7") and each of those directories will have 256 sub-directories.
The stashed data files appear under those.

=item B<algorithm> (optional, default "SHA-512")

The digest algorithm used to hash the files. This is passed to
C<< Digest->new() >>. The file's content is hashed and then stored using that
name, so you should select an algorithm that does not generate collisions.

=item B<dir_mask> (optional, default 0777)

The directory creation mask for the stash directories. This is merged with
yoru umask so the default is usually fine.

=item B<file_mask> (optional, default 0666)

The file creation mask for the stashed files. This is merged with your umask
setting so the default is usually fine.

=back

=cut

around new => sub {
  my($next) = shift;
  my($self) = shift;

  $self = $self->$next(@_);

  # FIXME: do something sane when *no* storage levels are defined
  my @buckets = split /,/, $self->{levels};
  #$self->{_buckets} = \@buckets;
  $self->{_nhash} = new Algorithm::Nhash @buckets;

  return $self;
};

my $digest2path = sub {
  my($self, $digest) = @_;

  return file($self->{root},
              $self->{_nhash}->nhash($digest),
              $digest,
             );
};

# FIXME/TESTME: zero length files causes $readfile to fail

my $readfile = sub {
  my($self, $path) = @_;

  # FIXME: is this good enough to avoid dirs?
  -f $path or die "Can't read $path: not a file";
  my $fh = new IO::File $path, 'r'
    or die "Can't read $path: $!";
  $fh->binmode;
  local $/;
  return "".<$fh>;
};

=item B<store_file>

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

=item B<store_string>

 my $id = $store->store_string('Hello, world');

This copies the string's contents into the stash. In scalar context it
returns the file's ID. In list context it returns an (ID, string length)
tuple.

=cut

sub store_string {
  my($self, $string) = @_;

  croak "Can't store an undefined value"
    unless defined $string;

  my $digester = new Digest($self->{algorithm});
  $digester->add($string);
  my $digest = $digester->hexdigest;
  my $path = $self->$digest2path($digest);

  unless(-e $path) { # skip rewrite if the file already exists
    my $parent = $path->dir;
    $parent->mkpath(0, $self->{dir_mask})
      unless -d $parent;
    
    my $unique = file($path->dir, $path->basename.".$hostname.$$");
    
    my $mode = O_WRONLY | O_CREAT;
    # FIXME: enable clobber and various other safety strategies
    #$mode |= O_EXCL unless $mayclobber;
    
    my $fh = new IO::File $unique, $mode, $self->{file_mask}
      or die "Can't create $unique: $!";
    $fh->binmode;
    print $fh $string;
    $fh->close;
    
    rename $unique, $path
      or die "Could not rename $unique to $path: $!";
  }
    
  return wantarray ? ($digest, length $string) : $digest;
}

=item B<fetch_file>

 my $path = $store->fetch_file($id);

Given an ID, will return the path to the stashed copy of the file, or undef
if no file with that ID has ever been stored.

Note that the path refers to the master copy of the file within the stash so
you will need to copy the file if you are going to potentially modify it.

=cut

sub fetch_file {
  my($self, $digest) = @_;

  my $path = $self->$digest2path($digest);
  return unless -f $path;
  return $path;
}

=item B<fetch_string>

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

=item B<exists>

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

=back

=head1 BUGS

This does not currently check for hash collisions.

You cannot provide a hashing algorithm that is not a Digest::* derivative.

=head1 SEE ALSO

File::HStore implements a similar idea.

=head1 AUTHOR

All code and documentation by Peter Corlett <abuse@cabal.org.uk>.

=head1 COPYRIGHT

Copyright (C) 2008 Peter Corlett <abuse@cabal.org.uk>. All rights
reserved.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SUPPORT / WARRANTY

This is free software. IT COMES WITHOUT WARRANTY OF ANY KIND.

=cut

1;
