use strict;
use warnings;
use utf8;
use ExtUtils::MakeMaker;

my $GITHUB_URL  = 'https://github.com/CNAG-Biomedical-Informatics/convert-pheno';

WriteMakefile(
  NAME          => 'Convert::Pheno',
  ABSTRACT_FROM => 'bin/convert-pheno',
  AUTHOR        => q{Manuel Rueda <mrueda@cpan.org>},
  LICENSE       => 'perl',
  VERSION_FROM  => 'lib/Convert/Pheno.pm',
  META_MERGE    => {
    'dynamic_config' => 0,
    'meta-spec'      => {version   => 0},
    'no_index'       => {directory => [qw(api docs db ex t)]},
    'prereqs'        => {runtime   => {requires => {perl => '5.30'}}},
    'resources'      => {
      bugtracker => {web => "$GITHUB_URL/issues"},
      homepage   => $GITHUB_URL,
      license    => ['http://www.opensource.org/licenses/artistic-license-2.0'],
      repository => {type => 'git', url => "$GITHUB_URL.git", web => $GITHUB_URL},
    },
    'x_contributors' => [],
  },
  PREREQ_PM     => {},
  EXE_FILES => ['bin/convert-pheno'],
  TEST_REQUIRES => {'Test::More' => '1.30'},
  test          => {TESTS        => 't/*.t'}
);
