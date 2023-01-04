# Supported formats

<figure markdown>

<!--     datasets o-- runs : 1..n
    datasets o-- analyses : 1..n
    datasets o-- biosamples : 1..n
    datasets o-- individuals : 1..n
 -->
```mermaid
%%{init: {'theme':'forest'}}%%
graph LR
  A[Beacon v2 Models] -->|bff2pxf| B[Phenopackets v2]
  C[CDISC-ODM] -->|cdisc2bff| A;
  D[OMOP-CDM] -->|omop2bff| A;
  B -->|pxf2bff| A;
  C -->|cdisc2pxf| B;
  D -->|omop2pxf| B;
```
  <figcaption>Convert-Pheno supported data conversions</figcaption>
</figure>

=== "Input formats:"

    * [Beacon v2 Models (JSON)](bff.md)
    * [Phenopacket v2 (JSON)](pxf.md)
    * [OMOP-CDM (SQL export / CSV)](omop-cdm.md)
    * [REDCap exports (CSV)](redcap.md)
    * [CDISC-ODM v1 (XML)](cdisc.md)

=== "Output formats (Jan-2023):"

    * [Beacon v2 Models (JSON](bff.md)
    * [Phenopacket v2 (JSON)](pxf.md)
