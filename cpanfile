# No specific version needed

# bin and lib
requires 'JSON::XS';
requires 'YAML::XS';
requires 'Path::Tiny';
requires 'Term::ANSIColor';
requires 'Text::CSV_XS';
requires 'Sort::Naturally';
requires 'DBI';
requires 'DBD::SQLite';
requires 'Mojolicious::Lite';
requires 'XML::Fast';

# for t/protobuff.t (only local dev)
#requires 'Inline::Python';

# for utils
requires 'JSON::Validator';         # pxf-validator

# for api
requires 'IO::Socket::SSL';
