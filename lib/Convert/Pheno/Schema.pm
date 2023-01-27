package Convert::Pheno::Schema;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Moo;
use File::Spec::Functions qw(catfile);
use JSON::Validator;
use Term::ANSIColor qw(:constants);
use Convert::Pheno::IO;

# Declate attribute classes
has data => (
    is       => 'ro',
    required => 1
);
has debug => (
    is       => 'ro',
    required => 1
);
has schema_file => (
    is       => 'ro',
    required => 1
);

# The BUILD method is called after an object is created
sub BUILD {

    my $self = shift;
    $self->{schema} =
      io_yaml_or_json( { filepath => $self->{schema_file}, mode => 'read' } )
      ;    # setter
}

#########################
#########################
#  SCHEMA VALIDATION    #
#########################
#########################

sub json_validate {

    my $self   = shift;
    my $data   = $self->{data};
    my $schema = $self->{schema};
    my $debug  = $self->{debug};

    # DEBUG => we self-validate the schema
    self_validate($schema) if $debug;

    # Create object and load schema
    my $jv = JSON::Validator->new;

    # Load schema in object
    $jv->schema($schema);

    # Validate data
    my @errors = $jv->validate($data);

    # Show error if any
    say_errors( \@errors ) and die if @errors;
    return 1;
}

sub self_validate {

    my $validator = JSON::Validator::Schema->new(shift);
    my @errors    = $validator->is_invalid;
    say BOLD RED
"ERROR: The schema does not follow JSON Schema specification\nSee https://json-schema.org/draft/2020-12/schema"
      and die
      if $validator->is_invalid;
}

sub say_errors {

    my $errors = shift;
    if ( @{$errors} ) {
        say BOLD RED( join "\n", @{$errors} ), RESET;
    }

    #else {
    #    say BOLD GREEN 'Hurray! No errors found', RESET;
    #}
    return 1;
}
1;
