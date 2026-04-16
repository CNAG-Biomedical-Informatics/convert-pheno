# Supported formats

This page gives a compact overview of the formats that `Convert-Pheno` can read and write. Internally, most conversions go through `BFF` first, and then continue to the requested output format when needed.

!!! Note
    `openEHR` support is currently **experimental** and currently limited to **canonical composition input** with `BFF` output.

```mermaid
%%{init:{'theme':'neutral'}}%%
graph LR
  subgraph "Target model"
    A[Beacon v2 Models]
  end

  A -->|bff2pxf| B[Phenopackets v2]
  C[REDCap] -->|redcap2pxf| B
  D[OMOP-CDM] -->|omop2bff| A
  E[CDISC-ODM] -->|cdisc2bff| A
  F[CSV] -->|csv2bff| A
  B -->|pxf2bff| A
  C -->|redcap2bff| A
  D -->|omop2pxf| B
  E -->|cdisc2pxf| B
  F -->|csv2pxf| B
  A -->|bff2omop| D
  F -->|csv2omop| D
  E -->|cdisc2omop| D
  C -->|redcap2omop| D
  B -->|pxf2omop| D

  style A fill:#6495ED,stroke:#6495ED
  style B fill:#FF7F50,stroke:#FF7F50
  style C fill:#FF6965,stroke:#FF6965
  style D fill:#3CB371,stroke:#3CB371
  style E fill:#DDA0DD,stroke:#DDA0DD
  style F fill:#FFFF00,stroke:#FFFF00

  linkStyle 1,7,8,9,11,12,13 stroke:#0000FF,stroke-width:1px,stroke-dasharray:5 5,opacity:0.5;
```

<figcaption>Supported conversions. Dotted blue lines go via BFF, which serves as the internal center model for most workflows.</figcaption>

=== "Input formats"

    - [Beacon v2 Models (JSON | YAML)](bff.md)
    - [Phenopackets v2 (JSON | YAML)](pxf.md)
    - [OMOP-CDM (SQL export | CSV)](omop-cdm.md)
    - `openEHR` canonical JSON/YAML compositions (`experimental`)
    - [REDCap exports (CSV)](redcap.md)
    - [CDISC-ODM v1 (XML)](cdisc-odm.md)
    - [CSV raw data](csv.md)

=== "Main output formats"

    - [Beacon v2 Models (JSON | YAML)](bff.md)
    - [Phenopackets v2 (JSON | YAML)](pxf.md)
    - [OMOP CDM (CSV)](omop-cdm.md)

## Additional output formats

For `BFF` and `PXF` input, the tool can also produce simpler output forms that are easier to inspect or use downstream:

- flattened JSON or YAML with `--ojsonf`
- CSV with `--ocsv`
- JSON-LD or YAML-LD with `--ojsonld`

```mermaid
%%{init: {'theme':'neutral'}}%%
graph LR

  A[BFF] -->|bff2jsonf| C[JSON Flattened]
  A -->|bff2csv| D[CSV]
  A -->|bff2jsonld| E[JSON-LD]

  B[PXF] -->|pxf2jsonf| C
  B -->|pxf2csv| D
  B -->|pxf2jsonld| E

  style A fill:#6495ED,stroke:#6495ED
  style B fill:#FF7F50,stroke:#FF7F50
  style C fill:#FFFF00,stroke:#FFFF00
  style D fill:#E0E0E0,stroke:#E0E0E0
  style E fill:#9999FF,stroke:#9999FF
```

<figcaption>Additional output formats from BFF and PXF.</figcaption>

!!! Note "Why BFF matters in the diagrams"
    `BFF` is the internal center model for most conversions. User-facing output, however, is not limited to `BFF`: the toolkit also supports `PXF` and `OMOP CDM` output paths.
