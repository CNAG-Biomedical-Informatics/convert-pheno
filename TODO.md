# TODO

## CDISC ODM follow-up validation

The version-aware ODM 1.3 and 2.0 Snapshot pipeline is implemented for 0.34
with synthetic regression fixtures. Broaden the evidence before removing the
experimental label from generic and OpenClinica ODM profiles.

- Add an attributed ODM 2.0 fixture from an official CDISC example and validate
  it against the corresponding XML schema
- Obtain an anonymized OpenClinica ODM 1.3 Full export with extensions,
  acknowledge its source, and compare its normalized records with the EDC data
- Exercise additional independently produced ODM snapshots and document any
  intentionally unsupported extension structures

## cBioPortal follow-up

Clinical cBioPortal study input is implemented for 0.34 with directory and ZIP
package support, entity-aware BFF output, optional Mapping V2 augmentation,
and PXF and OMOP-CDM routes. The attributed DataHub fixture passes the official
cBioPortal validator in no-portal mode, and generated target files pass the
corresponding BFF and OMOP validators.

- Exercise independently produced study packages and incorporate differences
  in project-specific clinical attributes
- Add timeline data after defining mappings for relative dates, treatments,
  procedures, measurements, and specimen events
- Defer mutation, copy-number, expression, fusion, and structural-variant
  files until BFF `genomicVariations`, `analyses`, and `runs` are supported

## mCODE and Dataset-XML follow-up

mCODE 4.0 profile detection and primary cancer stage mapping are implemented
inside the FHIR R4 route for 0.34. CDISC Dataset-XML v1.0 input with required
Define-XML v2 metadata is also implemented through the shared SDTM mapper.

- Exercise mCODE with independently generated oncology Bundles and assess
  additional first-class mappings only where BFF has an appropriate target
- Exercise Dataset-XML from multiple generators with Define-XML 2.0 and 2.1
- Evaluate a bounded-memory Dataset-XML reader if multi-million-row studies
  become a practical use case

## Candidate inputs after 0.34

### Demand-driven candidates

- SAS XPORT with Define-XML is relevant for regulatory datasets, but binary
  XPT parsing should use a maintained implementation rather than new parser
  code in Convert-Pheno
- C-CDA/CCD could supply patient summaries and discharge documents, but its
  narrative content and template ecosystem make it a high-complexity route
- PCORnet CDM is feasible but overlaps substantially with OMOP-CDM and has a
  more geographically concentrated user base
- HL7 v2, i2b2, and proprietary EDC APIs should require a concrete user,
  stable contract, and representative fixture before implementation
# MEDIUM PRIORITY
* Pxf to BFF - genomicVariations

# LOW PRIORITY
* range_high and range_low OMOP value?
