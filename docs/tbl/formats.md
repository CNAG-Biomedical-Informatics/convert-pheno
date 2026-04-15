Input           | CLI        |  UI        | Module | Public API
        :---:   |   :---:    | :---:      | :---:  | :---:
Beacon v2 Models   | YES        | YES   | YES   | YES
CDISC-ODM          | YES        | YES   | YES   | **NO**
CSV                | YES        | **NO**| YES   | **NO**
Phenopackets v2    | YES        | YES   | YES   | YES
OMOP-CDM           | YES        | YES   | YES   | YES
REDCap             | YES        | YES   | YES   | **NO**

`Public API = NO` here means **not recommended as a public HTTP workflow**, even if advanced local or internal setups could still call the module with file-oriented parameters.

In practice, the public API is meant for **self-contained JSON payloads** such as `BFF`, `PXF`, and carefully prepared `OMOP-CDM`. Mapping-file-based conversions such as `CSV`, `REDCap`, and `CDISC-ODM` are better handled through the CLI.
