!!! Bug "Experimental feature"
    CSV conversion to [BFF](bff.md) and [PXF](pxf.md) data exchange formats is still in the development phase. Use it with caution.

## CSV with clinical data as input

!!! Note "Note"
    The purpose of this conversion method is to provide a user-friendly solution for those lacking the knowledge or resources to perform an ad hoc transformation of their raw clinical data into one of our output formats. We understand that handling clinical data can be a formidable task, and our goal is to accurately convert essential fields necessary for cross-study comparisons. Initially, `Convert-Pheno` was not designed for ingesting raw CSV files. However, we leveraged the functions we developed for converting REDCap projects, which also come in CSV format.

    If you use our tool and identify areas for improvement, please contact us or create a GitHub issue. Thank you.

=== "Command-line"

    When using the `convert-pheno` command-line interface, simply ensure the [correct syntax](usage.md) is provided.
    
    ```
    convert-pheno -icsv clinical_data.csv --mapping-file clinical_data_mapping.yaml -obff individuals.json
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
