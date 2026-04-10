`Convert-Pheno` core is a Perl module available at [CPAN](https://metacpan.org/pod/Convert::Pheno).

## Perl usage

The most direct programmatic interface is the Perl module itself:

```perl
use Convert::Pheno;

my $my_pxf_json_data = {
    phenopacket => {
        id      => "P0007500",
        subject => {
            id          => "P0007500",
            dateOfBirth => "unknown-01-01T00:00:00Z",
            sex         => "FEMALE"
        }
    }
};

my $convert = Convert::Pheno->new(
    {
        data   => $my_pxf_json_data,
        method => 'pxf2bff'
    }
);

my $data = $convert->pxf2bff;
```

That is the most complete and best-supported programmatic path in the project.

## Example scripts

- Perl example: [share/ex/perl.pl](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/share/ex/perl.pl)
- Python example: [share/ex/python.py](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/share/ex/python.py)

## About Python usage

A Python bridge is included in the repository for interoperability, but the underlying conversion logic still runs in Perl.

If you need Python integration, check:

- [Use as an API](use-as-an-api.md)
- [share/ex/python.py](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/share/ex/python.py)

!!! Note "Python support"
    The Python layer is a wrapper around the Perl module rather than an independent implementation of the conversion logic.
