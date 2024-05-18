
!!! Bug "Experimental feature"
    CSV conversion to [BFF](bff.md) and [PXF](pxf.md) data exchanges is still in the development phase. Use it with caution.

## CSV with clinical data as input

When using the `convert-pheno` command-line interface, simply ensure the [correct syntax](usage.md) is provided.

```
convert-pheno -icsv clinical_data.csv --mapping-file clinical_data_mapping.yaml -obff individuals.json
```

See examples:

=== "Input"
    * [CSV data](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/t/csv2bff/in/csv_data.csv)
    * [Mapping file](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/t/csv2bff/in/csv_mapping.yaml)

=== "Output"
    * [BFF](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/t/csv2bff/out/individuals.json)
