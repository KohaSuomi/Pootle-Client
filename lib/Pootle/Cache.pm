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

=head1 Pootle::Cache

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

use Params::Validate qw(:all);
use File::Slurp;

use Pootle::Logger;
my $l = bless({}, 'Pootle::Logger'); #Lazy load package logger this way to avoid circular dependency issues with logger includes from many packages

=head2 new

    my $c = new Pootle::Cache({
      cacheFile => 'pootle-client.cache', #Where the persistent cache should be saved?
    });

=cut

sub new($class, @params) {
  $l->debug("Initializing '$class' with parameters: ".$l->flatten(@params)) if $l->is_debug();
  my %self = validate(@params, {
    cacheFile => { default => 'pootle-client.cache'},
  });

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
    $cache = File::Slurp::read_file($s->cacheFile, { binmode => ':encoding(UTF-8)' });
  } catch { my $e = $_;
    if ($e =~ /sysopen: No such file or direc/) {
      open(my $FH, '>:encoding(UTF-8)', $s->cacheFile) or die "Couldn't initialize cache file=".$s->cacheFile.", Cwd=".Cwd::getcwd.", $!";
    }
    else {
      die $e;
    }
  };

  $s->{pCache} = _evalCacheContents($cache);
  $s->{tCache} = {};
}

=head2 _evalCacheContents
 @STATIC

Turn the raw cache contents into a perl data structure

 @PARAM1 String, raw cache contents
 @RETURNS HASHRef

=cut

sub _evalCacheContents($contents) {
  return eval "$contents";
}

sub saveCache($s) {
  $l->debug("saveCache():> Cache to '".$s->cacheFile."' is being persisted");
  open(my $FH, '>:encoding(UTF-8)', $s->cacheFile) or $l->logdie("Couldn't write cache file $s->cacheFile to ".Cwd::getcwd.", $!");
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

=head pFlush

Flushes the persistent cache from disk, forcing the Pootle::Client to fetch new values from the Pootle Server's API on subsequent API requests.

 @RETURNS whatever unlink returns, 0 on success, 1 on failure atleast. unlink docs don't say.

=cut

sub pFlush($s) {
  $l->debug("pFlush():> Cache to '".$s->cacheFile."' is being flushed");
  $s->{pCache} = {};
  my $rv = unlink $s->cacheFile;
  $l->error("pFlush():> Cache '".$s->cacheFile."' couldn't be flushed: $!") if $rv;
  return $rv;
}

sub DESTROY($s) {
  $l->debug("DESTROY():> Cache to '".$s->cacheFile."' is getting destroyed");
  eval { $s->saveCache(); };
  if ($@) {
    $l->warn($@);
  }
}

sub cacheFile($s)            { return $s->{cacheFile} }

=head2 Accessors

=over 4

=item B<cacheFile>

=cut

1;
