# Convert-Pheno Documentation

![Convert-Pheno logo](img/CP-logo.png){ width="110" }

`Convert-Pheno` is a toolkit for converting **clinical and phenotypic data** between supported exchange models such as `BFF`, `PXF`, `OMOP-CDM`, `REDCap`, `CDISC-ODM`, and mapped `CSV`.

!!! Note "Project status"
    The software is in active use and still evolving. Some conversion routes are more mature than others, so it is worth checking the format-specific pages before running a new workflow in production.

[Get started](what-is-convert-pheno.md){ .md-button .md-button--primary }
[See supported formats](supported-formats.md){ .md-button }
[Install the toolkit](download-and-installation.md){ .md-button }

## Typical workflows

Most users come to `Convert-Pheno` for one of these tasks:

- convert `PXF` to `BFF`
- convert `OMOP-CDM` exports to `BFF` or `PXF`
- convert `REDCap` or raw `CSV` data through a **mapping file**
- convert `BFF` to `PXF`, flattened `CSV`, flattened `JSON`, or `JSON-LD`

## Documentation map

- [Use](use-as-a-command-line-interface.md) if you want to **run the tool now**
- [Tutorial](tutorial.md) if you want **short guided examples**
- [Analysis](analysis.md) if you want to work with the generated `individuals.json`
- [Troubleshooting](troubleshooting.md) if something is not behaving as expected
- [Implementation](implementation.md) if you want the **architectural view**

## External components

- [Web App UI](https://cnag-biomedical-informatics.github.io/convert-pheno-ui/)
- [GitHub repository](https://github.com/CNAG-Biomedical-Informatics/convert-pheno)
