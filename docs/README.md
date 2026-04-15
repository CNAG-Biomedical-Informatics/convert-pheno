# Convert-Pheno Documentation

`Convert-Pheno` is a toolkit for converting **clinical and phenotypic data** between supported exchange models such as `BFF`, `PXF`, `OMOP-CDM`, `REDCap`, `CDISC-ODM`, and mapped `CSV`.

!!! Note "Project status"
    This documentation tracks `Convert-Pheno 0.30`.

    The software is in active use and still evolving. Some conversion routes are more mature than others, so it is worth checking the format-specific pages before running a new workflow in production.

[Get started](what-is-convert-pheno.md){ .md-button .md-button--primary }
[See supported formats](supported-formats.md){ .md-button }
[Install the toolkit](download-and-installation.md){ .md-button }

## Typical workflows

Most users come to `Convert-Pheno` for one of these tasks:

- convert `PXF` to `BFF` `individuals`, `biosamples`, `datasets`, and `cohorts`
- convert `OMOP-CDM` exports to `BFF` or `PXF`
- convert `REDCap` or raw `CSV` data through a **mapping file**
- convert `BFF` to `PXF`, flattened `CSV`, flattened `JSON`, or `JSON-LD`

!!! Note "API vs CLI"
    Use the HTTP API mainly for **self-contained JSON payloads** such as `BFF`, `PXF`, and carefully prepared `OMOP-CDM` requests.

    For mapping-file-based workflows such as `CSV`, `REDCap`, and `CDISC-ODM`, prefer the CLI.

## Documentation map

- [Use](use-as-a-command-line-interface.md) if you want to **run the tool now**
- [Tutorial](tutorial.md) if you want **short guided examples**
- [Use as an API](use-as-an-api.md) if you want the **HTTP contract and API support matrix**
- [Analysis](analysis.md) if you want to work with the generated `individuals.json`
- [Troubleshooting](troubleshooting.md) if something is not behaving as expected
- [Implementation](implementation.md) if you want the **architectural view**

## External components

- [Web App UI](https://cnag-biomedical-informatics.github.io/convert-pheno-ui/)
- [GitHub repository](https://github.com/CNAG-Biomedical-Informatics/convert-pheno)
