---
id: use-as-a-module
title: Module
sidebar_label: Module
slug: /use-as-a-module
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

`Convert-Pheno` core is a Perl module available at [CPAN](https://metacpan.org/pod/Convert::Pheno).

The module interface is mainly for developers embedding Convert-Pheno in local Perl or Python code. Most users should use the [command-line interface](use-as-a-command-line-interface).

Both bindings use the same module-style payload: `method`, `data`, and optional conversion arguments are passed together in one object. This is different from the HTTP(s) API, where request fields are grouped into `input`, `output`, and `options`.

## Language bindings

<Tabs groupId="module-language">
<TabItem value="perl" label="Perl" default>

The most direct programmatic interface is the Perl module itself:

```perl
use Convert::Pheno;

my $my_pxf_json_data = {
    phenopacket => {
        id      => "P0007500",
        subject => {
            id          => "P0007500",
            dateOfBirth => "2000-01-01T00:00:00Z",
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

BFF and PXF in-memory input remains owned by the caller. These conversions do
not empty or rewrite the supplied array or hash, so the same payload can be
inspected or reused after the call.

This is the native programmatic interface used by the project.

[View the complete Perl example](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/share/ex/perl.pl).

</TabItem>
<TabItem value="python" label="Python">

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
            "dateOfBirth": "2000-01-01T00:00:00Z",
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

[View the complete Python example](https://github.com/cnag-biomedical-informatics/convert-pheno/blob/main/share/ex/python.py).

</TabItem>
</Tabs>

For multi-document Dataset-JSON conversions, pass an array of decoded domain
documents as `data` and select `datasetjson2bff`, `datasetjson2pxf`, or
`datasetjson2omop`. The module groups those documents by `USUBJID`; it does not
expect the already grouped internal participant structure. OMOP output also
requires access to `ohdsi.db` through the normal module arguments.

For FHIR, pass one decoded R4 Bundle or an array of Bundles as `data` and select
`fhir2bff`, `fhir2pxf`, or `fhir2omop`. The module resolves Bundle references
and groups resources by Patient. The caller retains ownership of the supplied
Bundle data, so it can be inspected or reused after conversion. See the
[FHIR R4 guide](fhir) for the implemented resource profile.
