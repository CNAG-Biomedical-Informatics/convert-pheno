!!! Bug "Experimental"
    CDISC-ODM conversion is still experimental. It only works with controlled exports from REDCap projects.

**CDISC** stands for **C**linical **D**ata **I**nterchange **S**tandards **C**onsortium. **ODM** stands for **O**perational **D**ata **M**odel.

<figure markdown>
   ![CDISC](https://www.cdisc.org/themes/custom/cdiscd8/logo.svg){ width="400" }
   <figcaption>Image extracted from www.cdisc.org</figcaption>
</figure>


[CDISC](https://www.cdisc.org) has several [standards](https://www.cdisc.org/standards/data-exchange) for data exchange. From those, we accept as input [Operational Data Model (ODM)-XML](https://www.cdisc.org/standards/data-exchange/odm) it has become the [language of choice](https://en.wikipedia.org/wiki/Clinical_Data_Interchange_Standards_Consortium#ODM_and_EDC_integration) for representing case report form content in many electronic data capture (EDC) tools. 

!!! Abstract "About ODM-XML"
    ODM-XML is a vendor-neutral, platform-independent format for exchanging and archiving clinical and translational research data, along with their associated metadata, administrative data, reference data, and audit information.

## CDISC-ODM as input

=== "Command-line"

    !!! Info "ODM versions"
        We're accepting CDISC-ODM v1 (XML). Currently, v2 is in the [process of being approved](https://www.cdisc.org/public-review/odm-v2-0).

    We'll need three files:

    1. CDISC-ODM v1 (XML)
    2. REDCap data dictionary (CSV)
    3. Configuration (mapping) file (YAML)

    ```
    convert-pheno -icdisc cdisc.xml --redcap-dictionary dictionary.csv --redcap-config config.yaml -obff individuals.json
    ```
    !!! Warning "About other CDISC data exchange standars"
        We are currently exploring [Dataset-XML](https://www.cdisc.org/standards/data-exchange/dataset-xml) (extension of ODM-XML) and the new [Dataset-JSON](https://wiki.cdisc.org/display/ODM2/Dataset-JSON) formats. The idea is to support them in the future.

