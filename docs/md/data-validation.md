!!! Example "Data validation"

    To ensure the integrity and validity of converted outputs, we employ **external validation tools during development and in unit tests**. Specifically, we used the [bff-tools validate](https://github.com/CNAG-Biomedical-Informatics/beacon2-cbi-tools?tab=readme-ov-file#bff-tools-script-binbff-tools) for Beacon Friendly Format (BFF) and [phenopacket-tools](http://phenopackets.org/phenopacket-tools/stable) for Phenotype Exchange Format (PXF). These validators were instrumental in ensuring converted data adhere to the respective schemas and standards; for example, conversions were validated until the output was 100% compliant with the target schema. The same validation process is applied to Beacon v2 and OMOP CDM outputs. By preserving non-mapped variables where appropriate and applying rigorous validation, we aim to mitigate information loss and maximise fidelity of the converted data.

    **Important:** Convert-Pheno **does not validate your input data**. Input validation is out of scope for the software. If fields are missing or malformed, Convert-Pheno will handle these cases internally and apply default values where appropriate, but it will not verify that your source files are complete or correct. We therefore recommend validating and cleaning source files before conversion.

    See:

    * [bff-tools validate](https://github.com/CNAG-Biomedical-Informatics/beacon2-cbi-tools?tab=readme-ov-file#bff-tools-script-binbff-tools)
    * [phenopacket-tools)](http://phenopackets.org/phenopacket-tools/stable)
    * [OMOP CSV Validator](https://github.com/CNAG-Biomedical-Informatics/omop-csv-validator)
