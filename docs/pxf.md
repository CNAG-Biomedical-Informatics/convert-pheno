# Phenopacket v2 - PXF

**PXF** stands for **P**henotype e**X**change **F**ormat.

Phenopacket [documentation](https://phenopacket-schema.readthedocs.io/en/latest/basics.html).

## PXF as input

### Command-line

If you're using a Beacon v2 JSON file with the `convert-pheno` command-line interface just provide the right [syntax](https://github.com/mrueda/convert-pheno#synopsis):

Note that the file can consist of a single individual or multiple ones (JSON array).

```
convert-pheno -ipxf phenopacket.json -obff individuals.json
```

### Module

The idea is that we will pass the essential information as a hash (Perl) or dictionary (Python).


`Perl`
```Perl
$bff = {
     data => $my_bff_json_data,
     method => 'pxf2bff'
};

```

`Python`
```Python
bff = {
     "data : my_bff_json_data,
     "method" : "pxf2bff"
}
```

### API
```
{
 "data": {...}
 "method": "pxf2bff"
}
```
