---
title: Data Validation
sidebar_label: Data Validation
---

:::tip[Data validation]

Convert-Pheno uses external validators during development where practical: `bff-tools validate` from [beacon2-cbi-tools](https://github.com/CNAG-Biomedical-Informatics/beacon2-cbi-tools) for Beacon/BFF output, the extended `xt/protobuff.t` protobuf parsing test for PXF output, and [omop-csv-validator](https://github.com/CNAG-Biomedical-Informatics/omop-csv-validator) for OMOP CSV output. For BFF mappings, validator failures are used to refine runtime mappings, defaults, and type coercions until generated entity files validate against the Beacon v2 schemas.

**Important:** Convert-Pheno **does not validate your input data**. Source files should be checked before conversion.

See [Output Validation](../output-validation) for details.
:::
