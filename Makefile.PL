use strict;
use warnings;
use utf8;
use ExtUtils::MakeMaker;
use File::ShareDir::Install;

install_share dist => 'share';

my $GITHUB_URL = 'https://github.com/CNAG-Biomedical-Informatics/convert-pheno';

WriteMakefile(
    NAME          => 'Convert::Pheno',
    ABSTRACT_FROM => 'lib/Convert/Pheno.pm',
    AUTHOR        => q{Manuel Rueda <mrueda@cpan.org>},
    LICENSE       => 'perl',
    VERSION_FROM  => 'lib/Convert/Pheno.pm',
    META_MERGE    => {
        'dynamic_config' => 0,
        'meta-spec' => { version   => 0 },
        'no_index'  => { directory => [qw(docs t)] },
        'prereqs'   => { runtime   => { requires => { perl => '5.026000' } } },
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
    PREREQ_PM => {
        'JSON::XS'                       => '4.03',
        'YAML::XS'                       => '0.88',
        'Path::Tiny'                     => '0.144',
        'Term::ANSIColor'                => '5.01',
        'Text::CSV_XS'                   => '1.50',
        'Text::Similarity'               => '0.13',
        'Text::Levenshtein::XS'          => '0.503',        
        'Sort::Naturally'                => '1.03',
        'File::ShareDir::ProjectDistDir' => '1.000009',
        'DBI'                            => '1.643',
        'Moo'                            => '2.005005',
        'DBD::SQLite'                    => '1.72',
        'Mojolicious'                    => '9.33',
        'XML::Fast'                      => '0.17',
        'JSON::Validator'                => '5.14',
        'Types::Standard'                => '2.004000',
         #'Test::Deep'                     => '1.204',
         #'Test::Exception'                => '0.43',
         #'Test::Warn'                     => '0.37',
        'Data::Leaf::Walker' => '0.21',
        'Hash::Fold'         => '1.0.0',
        'JSONLD'             => '0.006',
        'Devel::Size'        => '0.84'

         #'IO::Socket::SSL'              => '2.083'
         #'Mojolicious::Plugin::OpenAPI' => '5.09'
    },
    EXE_FILES     => ['bin/convert-pheno'],
    TEST_REQUIRES => {
        'Test::More'      => '1.30',
        'Test::Deep'      => '1.204',
        'Test::Exception' => '0.43',
        'Test::Warn'      => '0.37'
    },
    test               => { TESTS => 't/*.t' },
    CONFIGURE_REQUIRES => {
        'File::ShareDir::Install' => '0.14',
        'ExtUtils::MakeMaker'     => '7.70',
    }
);

package MY;
use File::ShareDir::Install 'postamble';
