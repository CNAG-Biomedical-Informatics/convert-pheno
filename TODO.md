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

## Candidate inputs after 0.34

### Priority 1: cBioPortal clinical study packages

Add a dedicated `-icbioportal` input for a cBioPortal study directory or ZIP.
This is a strong fit for oncology because the study package explicitly links
patient, sample, study, cohort, timeline, and molecular data. The first scope
must be described as cBioPortal clinical study input rather than complete
cBioPortal support.

- Discover data files through their cBioPortal meta files rather than fixed
  filenames
- Map study metadata to BFF `datasets`
- Map patient clinical attributes to `individuals`
- Map sample clinical attributes and patient/sample links to `biosamples`
- Resolve case lists to `cohorts`, including sample-to-patient membership
- Process project-specific patient and sample columns through a mapping file
- Preserve original values under `info.cbioportal` unless `--no-source-info`
  is selected
- Accept timeline data in a later phase after defining mappings for relative
  dates, treatments, procedures, measurements, and specimen events
- Defer mutation, copy-number, expression, fusion, and structural-variant
  files until BFF `genomicVariations`, `analyses`, and `runs` are supported
- Use an attributed fixture from the official cBioPortal DataHub and validate
  it with the cBioPortal dataset validator before validating generated outputs

### Priority 2: mCODE FHIR oncology profile

Extend the existing `-ifhir` route rather than introducing another input
format. Add profile-aware mappings for primary cancer conditions, TNM staging,
treatments, genomics reports, and other mCODE structures while retaining the
generic FHIR R4 fallback and provenance behavior.

### Priority 3: CDISC Dataset-XML with Define-XML

Add `-idataset-xml` by implementing an XML dataset reader and reusing the
existing Dataset-JSON SDTM normalization and semantic mappings. Use Define-XML
metadata when supplied and keep Dataset-XML distinct from operational ODM
clinical data.

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
