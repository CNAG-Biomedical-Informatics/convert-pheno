# CDISC - ODM

**CDISC** stands for **C**linical **D**ata **I**nterchange **S**tandards **C**onsortium.
**ODM** stands for **O**perational **D**ata **M**odel.

[CDISC](https://www.cdisc.org) has several [standards](https://www.cdisc.org/standards/data-exchange) for data exchange. From those, we accept as input **Operational Data Model (ODM)-XML**. ODM-XML is a vendor-neutral, platform-independent format for exchanging and archiving clinical and translational research data, along with their associated metadata, administrative data, reference data, and audit information.

!!! Info "ODM versions"
    We're accpeting CDISC-ODM v1 (XML). Currently, v2 is in the [process of being approved](https://www.cdisc.org/public-review/odm-v2-0).

## CDISC-ODM as input

!!! Danger "Experimental"
    CDISC-ODM conversion is still experimental. It only works with controlled exports from REDCap projects.

REDCap projects are by definition “**free format**”, that is, is up to the project creator to establish the identifiers for the variables, data dictionaries, etc.

### Command-line

Note that the we need two files, one `XML` for CDISC-ODM data and a `csv` for the dictionaries.

```
convert-pheno -icdisc cdisc.xml --redcap-dictionary dictionary.csv -obff individuals.json
```
