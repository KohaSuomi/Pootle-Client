# Copyright (C) 2017 Koha-Suomi
#
# This file is part of Pootle-Client.

package Pootle::Cache;

use Modern::Perl '2015';
use utf8;
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
use feature 'signatures'; no warnings "experimental::signatures";
use Carp::Always;
use Try::Tiny;
use Scalar::Util qw(blessed);
use Data::Dumper;
use Cwd;

=head2 Pootle::Cache

Persist API results somewhere to prevent excessive spamming of the Pootle-Client.
These changes might persist over the current process exiting.

=head2 Transient cache

Pootle::Cache has a transient portion, values stored here disappear after the program exits.
You can access this cache with methods tGet, tPut, t*, ...
If you want to refresh the results of methods, which have the
    "@CACHED Transiently" -tag
you must flush the transient cache using:
    $cache->tFlush();
or restart the program.

=head2 Persistent cache

Pootle::Cache has a persistent portion, values stored here will be flushed to the on-disk cache file, if the program exits normally.
You can access this cache with methods pGet, pPut, p*, ...
If you want to refresh the results of methods, which have the
    "@CACHED Persistently" -tag
you must flush the persistent cache using:
    $cache->pFlush();

=cut

use File::Slurp;

use Pootle::Logger;
my $l = bless({}, 'Pootle::Logger'); #Lazy load package logger this way to avoid circular dependency issues with logger includes from many packages

our $cacheFile = 'pootle-api.cache';

sub new($class, $params) {
  $l->debug("Initializing ".__PACKAGE__." with parameters: ".$l->flatten($params)) if $l->is_debug();

  my %self = %$params;
  my $s = \%self;

  bless($s, $class);

  $s->loadCache();

  return $s;
}

=head2 loadCache

Loads cache from disk, if cache is not present, tests for file permissions to persist one.

=cut

sub loadCache($s) {

  my $cache = "{}";
  try {
    $cache = File::Slurp::read_file($cacheFile, { binmode => ':encoding(UTF-8)' });
  } catch { my $e = $_;
    if ($e =~ /sysopen: No such file or direc/) {
      open(my $FH, '>:encoding(UTF-8)', $cacheFile) or die "Couldn't initialize cache file $cacheFile to ".Cwd::getcwd.", $!";
    }
    else {
      die $e;
    }
  };

  $cache = eval "$cache";
  $s->{pCache} = $cache;
  $s->{tCache} = {};
}

sub saveCache($s) {
  open(my $FH, '>:encoding(UTF-8)', $cacheFile) or die "Couldn't write cache file $cacheFile to ".Cwd::getcwd.", $!";
  print $FH Data::Dumper->new([$s->{cache}],[])->Terse(1)->Indent(1)->Varname('')->Maxdepth(0)->Sortkeys(1)->Quotekeys(1)->Dump();
  close($FH);
}

sub flushCaches($s) {
  $s->tFlush();
  $s->pFlush();
}

=head2 tSet

Store a value to the transient in-memory store. This will never be flushed to disk.

=cut

sub tSet($s, $k, $v) {
  return $s->{tCache}->{$k} = $v;
}

sub tGet($s, $k) {
  return $s->{tCache}->{$k};
}

sub tFlush($s) {
  $s->{tCache} = {};
}

=head2 pSet

Store a value to the persistent in-memory store

=cut

sub pSet($s, $k, $v) {
  return $s->{pCache}->{$k} = $v;
}

sub pGet($s, $k) {
  return $s->{pCache}->{$k};
}

sub pFlush($s) {
  $s->{pCache} = {};
  unlink $cacheFile;
}

sub DESTROY($s) {
  eval { $s->saveCache(); };
  if ($@) {
    warn $@;
  }
}

1;
