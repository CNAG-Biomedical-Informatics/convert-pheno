# Supported formats

<figure markdown>

```mermaid
%%{init: {'theme':'neutral'}}%%
graph LR
  A[Beacon v2 Models] -->|bff2pxf| B[Phenopackets v2]
  C[CDISC-ODM] -->|cdisc2bff| A;
  D[OMOP-CDM] -->|omop2bff| A;
  B -->|pxf2bff| A;
  C -->|cdisc2pxf| B;
  D -->|omop2pxf| B;

  style A fill: #6495ED
  style A stroke: #6495ED
  style B fill: #FF7F50
  style B stroke: #FF7F50
  style C fill: #DDA0DD
  style C stroke: #DDA0D
  style D fill: #3CB371
  style D stroke: #3CB371

```
  <figcaption>Convert-Pheno supported data conversions</figcaption>
</figure>

=== "Input formats:"

    * [Beacon v2 Models (JSON | YAML)](bff.md)
    * [Phenopacket v2 (JSON | YAML)](pxf.md)
    * [OMOP-CDM (SQL export | CSV)](omop-cdm.md)
    * [REDCap exports (CSV)](redcap.md)
    * [CDISC-ODM v1 (XML)](cdisc.md)

=== "Output formats (Jan-2023):"

    * [Beacon v2 Models (JSON | YAML)](bff.md)
    * [Phenopacket v2 (JSON | YAML)](pxf.md)

    !!! Question "Why start with these two?"
        [Beacon v2](https://docs.genomebeacons.org) and [Phenopackets v2](https://phenopacket-schema.readthedocs.io/en/latest) are data exchange standards from the [G4AGH](https://www.ga4gh.org).

