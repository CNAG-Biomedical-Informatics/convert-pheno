# Beacon v2 - BFF

**BFF** stands for **B**eacon **F**riendly **F**ormat.

The BFF consists of 7 `JSON` files that match the 7 entry types of the [Beacon v2 default models](https://docs.genomebeacons.org/models).

From these 7 files, in many occasions only `individuals.json` is the file containing [phenotypic data](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema).

## BFF as input

### Command-line

If you're using a Beacon v2 JSON file with the `convert-pheno` command-line interface just provide the right [syntax](https://github.com/mrueda/Convert-Pheno#synopsis):

Note that the file can consist of a single individual or multiple ones (JSON array).

```
convert-pheno -ibff individuals.json -opxf phenopacket.json
```

### Module

The idea is that we will pass the essential information as a hash (Perl) or dictionary (Python).


```Perl
$bff = {
     data => $my_bff_json_data,
     method => $method
};

```


```Python
bff = {
     "data : my_bff_json_data,
     "method" : "bff2pxf"
}
```

### API

The data will be sent as `POST` to the API's URL (see more info [here](use-as-an-api.md).
```
{
 "data": {...}
 "method": "bff2pxf"
}
```
