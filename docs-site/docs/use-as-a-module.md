---
title: Module
sidebar_label: Module
---

`Convert-Pheno` core is a Perl module available at [CPAN](https://metacpan.org/pod/Convert::Pheno).

The module interface is mainly for developers embedding Convert-Pheno in local Perl or Python code. Most users should use the [command-line interface](use-as-a-command-line-interface).

Both bindings use the same module-style payload: `method`, `data`, and optional conversion arguments are passed together in one object. This is different from the HTTP(s) API, where request fields are grouped into `input`, `output`, and `options`.

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

This is the native programmatic interface used by the project.

## Python usage

Python code can use the local binding without starting the HTTP(s) API:

```python
import json
import sys

# Provide the path to <convert-pheno/lib> when running from the repository
# checkout instead of an installed Python environment.
sys.path.append("../../lib/")
from convertpheno import PythonBinding

my_pxf_json_data = {
    "phenopacket": {
        "id": "P0007500",
        "subject": {
            "id": "P0007500",
            "dateOfBirth": "unknown-01-01T00:00:00Z",
            "sex": "FEMALE",
        },
    }
}

payload = {
    "method": "pxf2bff",
    "data": my_pxf_json_data,
    "test": 1,
}

convert = PythonBinding(payload)
print(json.dumps(convert.convert_pheno(), indent=4, sort_keys=True))
```

The Python binding shells out to the Perl JSON bridge internally, so it is a convenience layer over the same conversion engine rather than a separate implementation.

## Example scripts

- Perl example: [share/ex/perl.pl](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/share/ex/perl.pl)
- Python example: [share/ex/python.py](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/share/ex/python.py)

## About Python usage

A Python bridge is included in the repository for interoperability, but the underlying conversion logic still runs in Perl.

If you need Python integration, check:

- [share/ex/python.py](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/share/ex/python.py)

:::note[Python support]
The Python layer is a wrapper around the Perl module rather than an independent implementation of the conversion logic.
:::
