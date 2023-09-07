Internally, all models are mapped to the [Beacon v2 Models](bff.md). If the output is set to [Phenopackets v2](pheonpacket.md) then a second step (`bff2pxf`) is performed (see diagram below).

!!! Hint "Why use Beacon v2 as target model?"
    The reason for selecting Beacon v2 Model as the target for the conversion is its **schema flexibility**, which allows for the inclusion of variables that may not be present in the original schema definition. In contrast, Phenopackets v2 has stricter schema requirements. This flexibility offered by Beacon v2 schemas enables us to handle a wider range of phenotypic data and accommodate **additional variables**, enhancing the utility and applicability of our tool.

```mermaid
%%{init: {'theme':'neutral'}}%%
graph LR
  subgraph "Step 1:Conversion to Beacon v2 Models"
  B[Phenopackets v2] -->|pxf2bff| A
  C[REDCap] -->|redcap2bff| A[Beacon v2 Models]
  D[OMOP-CDM] -->|omop2bff| A
  E[CDISC-ODM] -->|cdisc2bff| A
  end

  subgraph "Step 2:BFF to PXF"
  A --> |bff2pxf| F[Phenopackets v2]
  end

  style A fill: #6495ED, stroke: #6495ED
  style B fill: #FF7F50, stroke: #FF7F50
  style C fill: #FF6965, stroke: #FF6965
  style D fill: #3CB371, stroke: #3CB371
  style E fill: #DDA0DD, stroke: #DDA0DD
```
<figcaption>Convert-Pheno internal mapping steps</figcaption>

!!! Question "How are variables that cannot be mapped handled during the conversion process?"

    During the conversion process, handling variables that **cannot be directly mapped** can result in one of two scenarios:

    1. If the target format accommodates extra properties in a given term (BFF does), unmapped variables find a place under the `_info` property. This is a usual occurrence in conversions from OMOP-CDM to BFF.
   
    2. When a variable corresponds with other entities in the Beacon v2 Models, it gets stored within the `info` term of BFF. For instance, `biosamples` from PXF files are housed in BFF `info` under `info.phenopacket.biosamples`.
