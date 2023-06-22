use strict;
use warnings;
use utf8;
use ExtUtils::MakeMaker;

my $GITHUB_URL = 'https://github.com/CNAG-Biomedical-Informatics/convert-pheno';

WriteMakefile(
    NAME          => 'Convert::Pheno',
    ABSTRACT_FROM => 'bin/convert-pheno',
    AUTHOR        => q{Manuel Rueda <mrueda@cpan.org>},
    LICENSE       => 'perl',
    VERSION_FROM  => 'lib/Convert/Pheno.pm',
    META_MERGE    => {
        'dynamic_config' => 0,
        'meta-spec' => { version   => 0 },
        'no_index'  => { directory => [qw(api docs db ex t)] },
        'prereqs'   => { runtime   => { requires => { perl => '5.016' } } },
        'resources' => {
            bugtracker => { web => "$GITHUB_URL/issues" },
            homepage   => $GITHUB_URL,
            license    =>
              ['http://www.opensource.org/licenses/artistic-license-2.0'],
            repository =>
              { type => 'git', url => "$GITHUB_URL.git", web => $GITHUB_URL },
        },
        'x_contributors' => [],
    },
    PREREQ_PM => PREREQ_PM => {
        'JSON::XS'                     => '4.03',
        'YAML::XS'                     => '0.88',
        'Path::Tiny'                   => '0.144',
        'Term::ANSIColor'              => '5.01',
        'Text::CSV_XS'                 => '2.02',
        'Text::Similarity'             => '0.13',
        'Sort::Naturally'              => '1.03',
        'DBI'                          => '1.643',
        'Moo'                          => '2.005005',
        'DBD::SQLite'                  => '1.72',
        'Mojolicious::Lite'            => '9.33',
        'XML::Fast'                    => '0.17',
        'JSON::Validator'              => '5.14',
        'Types::Standard'              => '2.004000',
        'Test::Deep'                   => '1.204',
        'Test::Exception'              => '0.43',
        'Test::Warn'                   => '0.37',
        'PerlIO::gzip'                 => '0.20',
        'IO::Socket::SSL'              => '2.083',
        'Mojolicious::Plugin::OpenAPI' => '5.09'
    },
    EXE_FILES     => ['bin/convert-pheno'],
    TEST_REQUIRES => { 'Test::More' => '1.30' },
    test          => { TESTS        => 't/*.t' }
);
