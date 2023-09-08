# No specific version needed

# bin and lib
requires 'JSON::XS';
requires 'YAML::XS';
requires 'Path::Tiny';
requires 'Term::ANSIColor';
requires 'Text::CSV_XS';
requires 'Text::Similarity';
requires 'Sort::Naturally';
requires 'DBI';
requires 'Moo';
requires 'DBD::SQLite';
requires 'Mojolicious::Lite';
requires 'XML::Fast';
requires 'JSON::Validator';
requires 'IO::Socket::SSL';
requires 'Types::Standard';
requires 'File::ShareDir::ProjectDistDir';
requires 'Data::Leaf::Walker';

# t
requires 'Test::Deep';
requires 'Test::Exception';
requires 'Test::Warn';
requires 'IO::Uncompress::Gunzip';
#requires 'Inline::Python';      # for t/protobuff.t (only local dev)

# api
requires 'Mojolicious::Plugin::OpenAPI';
#requires 'Future::AsyncAwait';  # for async/wait     
