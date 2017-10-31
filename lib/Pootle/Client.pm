# Copyright (C) 2017 Koha-Suomi
#
# This file is part of Pootle::Client.

package Pootle::Client;

use Modern::Perl '2015';
use utf8;
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
use feature 'signatures'; no warnings "experimental::signatures";
use Carp::Always;
use Try::Tiny;
use Scalar::Util qw(blessed);

our $VERSION = '0.01';

=head2 Pootle::Client

Client to talk with Pootle API v1 nicely

See.
    https://pootle.readthedocs.io/en/stable-2.5.1/api/index.html
for more information about the API resources/data_structures this Client returns.

Eg. https://pootle.readthedocs.io/en/stable-2.5.1/api/api_project.html#get-a-project
maps to Pootle::Resource::Project locally.

=head2 Caches

See Pootle::Cache, for how the simple caching system works to spare the Pootle-Server from abuse

=head2 Synopsis

    my $papi = Pootle::Client->new({baseUrl => 'http://translate.example.com', credentials => 'username:password' || 'credentials.txt'});
    my $languages = $papi->languages();
    my $translationProjects = $papi->searchTranslationProjects($languages, Pootle::Filters->new({fullname => qr/^Project name/}));


=cut

use Pootle::Agent;
use Pootle::Cache;
use Pootle::Filters;
use Pootle::Resource::Language;
use Pootle::Resource::TranslationProject;
use Pootle::Resource::Store;
use Pootle::Resource::Unit;
use Pootle::Resource::Project;

use Pootle::Logger;
my $l = bless({}, 'Pootle::Logger'); #Lazy load package logger this way to avoid circular dependency issues with logger includes from many packages

sub new($class, $params) {
  $l->debug("Initializing ".__PACKAGE__." with parameters: ".$l->flatten($params)) if $l->is_debug();

  my %self = %$params;
  my $s = \%self;

  bless($s, $class);

  $s->{agent} = new Pootle::Agent($params);
  $s->{cache} = new Pootle::Cache($params);

  return $s;
}

=head2 language

@PARAM1 String, API endpoint to get the resource, eg. /api/v1/languages/124/
@RETURNS Pootle::Resource::Language

=cut

sub language($s, $endpoint) {
  my $contentHash = $s->a->request('get', $endpoint, {});
  return new Pootle::Resource::Language($contentHash);
}

=head2 languages

@RETURNS ARRAYRef of Pootle::Resource::Language, all languages in the Pootle database
@CACHED Transiently

=cut

sub languages($s) {
  return $s->c->tGet('/api/v1/languages/') if $s->c->tGet('/api/v1/languages/');
  my $contentHash = $s->a->request('get', '/api/v1/languages/', {});
  my $objs = $contentHash->{objects};
  for (my $i=0 ; $i<@$objs ; $i++) {
    $objs->[$i] = new Pootle::Resource::Language($objs->[$i]);
  }
  $s->c->tSet('/api/v1/languages/', $objs);
  return $objs;
}

=head2 findLanguages

Uses the API to find all languages starting with the given country code

@PARAM1 HASHRef of Filters, see Pootle::Filters->new();
@RETURNS ARRAYRef of Pootle::Resource::Language. All languages starting with the given code.
@CACHED Persistently

=cut

sub findLanguages($s, $filters) {
  my $cached = $s->c->pGet('findLanguages '.$l->flatten($filters));
  return $cached if $cached;

  my $objects = Pootle::Filters->new($filters)->filter( $s->languages() );

  $s->c->pSet('findLanguages '.$l->flatten($filters), $objects);
  return $objects;
}

=head2 translationProject

@PARAM1 String, API endpoint to get the resource, eg. /api/v1/translation-projects/124/
@RETURNS Pootle::Resource::TranslationProject

=cut

sub translationProject($s, $endpoint) {
  my $contentHash = $s->a->request('get', $endpoint, {});
  return new Pootle::Resource::TranslationProject($contentHash);
}

=head2 translationProjects

@UNIMPLEMENTED

This endpoint is unimplemented in the Pootle-Client. Maybe some day it becomes enabled. If it does, this should work out-of-box.

It might be better to use searchTranslationProjects() instead, since this API call can be really invasive to the Pootle-server.
Really depends on how many translation projects you are after.

@RETURNS ARRAYRef of Pootle::Resource::TranslationProject, all translation projects in the Pootle database
@CACHED Transiently
@THROWS Pootle::Exception::HTTP::MethodNotAllowed

=cut

sub translationProjects($s) {
  return $s->c->tGet('/api/v1/translation-projects/') if $s->c->tGet('/api/v1/translation-projects/');
  my $contentHash = $s->a->request('get', '/api/v1/translation-projects/', {});
  my $objs = $contentHash->{objects};
  for (my $i=0 ; $i<@$objs ; $i++) {
    $objs->[$i] = new Pootle::Resource::TranslationProject($objs->[$i]);
  }
  $s->c->tSet('/api/v1/translation-projects/', $objs);
  return $objs;
}

=head2 findTranslationProjects

@UNIMPLEMENTED

This endpoint is unimplemented in the Pootle-Client. Maybe some day it becomes enabled. If it does, this should work out-of-box.

Uses the API to find all translation projects matching the given search expressions

@PARAM1 HASHRef of Filters, see Pootle::Filters->new();
@RETURNS ARRAYRef of Pootle::Resource::TranslationProject. All matched translation projects.
@CACHED Persistently
@THROWS Pootle::Exception::HTTP::MethodNotAllowed

=cut

sub findTranslationProjects($s, $filters) {
  my $cached = $s->c->pGet('findTranslationProjects '.$l->flatten($filters));
  return $cached if $cached;

  my $objects = Pootle::Filters->new($filters)->filter( $s->translationProjects() );

  $s->c->pSet('findTranslationProjects '.$l->flatten($filters), $objects);
  return $objects;
}

=head2 searchTranslationProjects

@PARAM1 HASHRef, see Pootle::Filters->new(), Filters to pick desired languages
        or
        ARRAYRef of Pootle::Resource::Language
@PARAM2 HASHRef, see Pootle::Filters->new(), Filters to pick desired projects
        or
        ARRAYRef of Pootle::Resource::Project
@RETURNS ARRAYRef of Pootle::Resource::TranslationProject, matching the given languages and projects
@CACHED Persistently

=cut

sub searchTranslationProjects($s, $languageFilters, $projectFilters) {
  my $cached = $s->c->pGet('searchTranslationProjects '.$l->flatten($languageFilters).$l->flatten($projectFilters));
  return $cached if $cached;

  my $languages;
  if (ref($languageFilters) eq 'ARRAY' && blessed($languageFilters->[0]) && $languageFilters->[0]->isa('Pootle::Resource::Language')) {
    $languages = $languageFilters;
  }
  else {
    $languages = $s->findLanguages($languageFilters);
  }

  my $projects;
  if (ref($projectFilters) eq 'ARRAY' && blessed($projectFilters->[0]) && $projectFilters->[0]->isa('Pootle::Resource::Project')) {
    $projects = $projectFilters;
  }
  else {
    $projects = $s->findProjects($projectFilters);
  }

  my $sharedTranslationProjectsEndpoints = Pootle::Filters->new()->intersect($languages, $projects, 'translation_projects', 'translation_projects');
  my @translationProjects;
  foreach my $intersection (@$sharedTranslationProjectsEndpoints) {
    push(@translationProjects, $s->translationProject($intersection->attributeValue));
  }

  $s->c->pSet('searchTranslationProjects '.$l->flatten($languageFilters).$l->flatten($projectFilters), \@translationProjects);
  return \@translationProjects;
}

=head2 store

@PARAM1 String, API endpoint to get the resource, eg. /api/v1/stores/77/
@RETURNS Pootle::Resource::Store

=cut

sub store($s, $endpoint) {
  my $contentHash = $s->a->request('get', $endpoint, {});
  return new Pootle::Resource::Store($contentHash);
}

=head2 searchStores

@PARAM1 HASHRef, see Pootle::Filters->new(), Filters to pick desired languages
        or
        ARRAYRef of Pootle::Resource::Language
@PARAM2 HASHRef, see Pootle::Filters->new(), Filters to pick desired projects
        or
        ARRAYRef of Pootle::Resource::Project
@RETURNS ARRAYRef of Pootle::Resource::Store, matching the given languages and projects

=cut

sub searchStores($s, $languageFilters, $projectFilters) {
  my $cached = $s->c->pGet('searchStores '.$l->flatten($languageFilters).$l->flatten($projectFilters));
  return $cached if $cached;

  my $transProjs = $s->searchTranslationProjects($languageFilters, $projectFilters);

  my @stores;
  foreach my $translationProject (@$transProjs) {
    foreach my $storeUri (@{$translationProject->stores}) {
      push(@stores, $s->store($storeUri));
    }
  }

  $s->c->pSet('searchStores '.$l->flatten($languageFilters).$l->flatten($projectFilters), \@stores);
  return \@stores;
}

=head2 project

@PARAM1 String, API endpoint to get the project, eg. /api/v1/projects/124/
@RETURNS Pootle::Resource::Project

=cut

sub project($s, $endpoint) {
  my $contentHash = $s->a->request('get', $endpoint, {});
  return new Pootle::Resource::Project($contentHash);
}

=head2 projects

@RETURNS ARRAYRef of Pootle::Resource::Project, all projects in the Pootle database
@CACHED Transiently

=cut

sub projects($s) {
  return $s->c->tGet('/api/v1/projects/') if $s->c->tGet('/api/v1/projects/');
  my $contentHash = $s->a->request('get', '/api/v1/projects/', {});
  my $objs = $contentHash->{objects};
  for (my $i=0 ; $i<@$objs ; $i++) {
    $objs->[$i] = new Pootle::Resource::Project($objs->[$i]);
  }
  $s->c->tSet('/api/v1/projects/', $objs);
  return $objs;
}

=head2 findProjects

Uses the API to find all projects matching the given search expressions

@PARAM1 HASHRef of Filters, see Pootle::Filters->new();
@RETURNS ARRAYRef of Pootle::Resource::Project. All matched projects.
@CACHED Persistently

=cut

sub findProjects($s, $filters) {
  my $cached = $s->c->pGet('findProjects '.$l->flatten($filters));
  return $cached if $cached;

  my $objects = Pootle::Filters->new($filters)->filter( $s->projects() );

  $s->c->pSet('findProjects '.$l->flatten($filters), $objects);
  return $objects;
}

=head2 unit

@PARAM1 String, API endpoint to get the resource, eg. /api/v1/units/77/
@RETURNS Pootle::Resource::Unit

=cut

sub unit($s, $endpoint) {
  my $contentHash = $s->a->request('get', $endpoint, {});
  return new Pootle::Resource::Unit($contentHash);
}


##########    ###   ###
 ## ACCESSORS  ###   ###
##########    ###   ###

=head2 a

Shorthand to get the Pootle::Agent

=cut

sub a($s) { return $s->{agent} }

=head2 a

Shorthand to get the Pootle::Cache

=cut

sub c($s) { return $s->{cache} }

1;
