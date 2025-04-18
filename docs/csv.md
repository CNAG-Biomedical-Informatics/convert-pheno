!!! Warning "Experimental feature"
    CSV conversion to [BFF](bff.md), [PXF](pxf.md) and [OMOP CDM](omop-cdm.md) data exchange formats is still in the development phase. Use it with caution.

## CSV with clinical data as input

!!! Note "Note"
    This conversion method helps users who don't have the tools or expertise to transform their raw clinical data. It aims to convert **essential fields needed for comparing data across studies**.

    If you use our tool and identify areas for improvement, please contact us or create a GitHub issue. Thank you.

=== "Command-line"

    When using the `convert-pheno` command-line interface, simply ensure the [correct syntax](usage.md) is provided.

    !!! Warning "CSV Separator Notice"

        Please note that the default separator for CSV files is `;`. If your file uses a different character (e.g., `,` or `:`), please specify it using the `--sep` option.
    
    ```
    convert-pheno -icsv clinical_data.csv --mapping-file clinical_data_mapping.yaml -obff individuals.json --sep ,
    ```

    Please refer to the [Convert-Pheno tutorial](https://cnag-biomedical-informatics.github.io/convert-pheno/tutorial/#how-to-convert) for more information.
    
    !!! Question "How do I convert other Beacon v2 Models entities?"
        We recommend using the maintaned version of the original **Beacon v2 Reference Implementation** tools ([beacon2-ri-tools](https://github.com/mrueda/beacon2-ri-tools)).
    
    See examples:
    
    === "Input"
        * [CSV data](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/t/csv2bff/in/csv_data.csv)
        * [Mapping file](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/t/csv2bff/in/csv_mapping.yaml)
    
    === "Output"
        * [BFF](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/t/csv2bff/out/individuals.json)
        * [PXF](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/t/csv2pxf/out/pxf.json)
    
=== "API"

    While it is *technically possible* to perform a transformation via the `Convert-Pheno` API, we don't think this is how most people will transform CSV files (due to the need of the mapping file). Therefore, we recommend using the **command-line** version.

    --8<-- "tbl/formats.md"
