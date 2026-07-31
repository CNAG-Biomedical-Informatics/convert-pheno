# TODO

## 0.34: CDISC ODM v2.0 XML ClinicalData input

Add experimental input support for a bounded ODM v2.0 XML ClinicalData
profile. This is worthwhile because ODM v2 represents hierarchical,
operational clinical-study data that is not covered by the tabular
Dataset-JSON route.

ODM v2 is a backward-incompatible successor to ODM v1, not another
serialization of Dataset-JSON. The existing ODM v1 parser handles its
`FormData` and attribute-based item-value hierarchy; the current reference
mapping, dictionary, and event handling were developed from a REDCap ODM 1.3.1
export. ODM v2 instead places recursively nested `ItemGroupData` below study
events and stores item values in child `Value` elements. It also has richer
support for repeated structures, controlled terminology, queries, audit data,
signatures, and study design.

### Initial scope

- Accept ODM v2.0 XML snapshot documents containing `ClinicalData`
- Detect the input version strictly from both the namespace and `ODMVersion`
- Support `SubjectData`, `StudyEventData`, recursively nested
  `ItemGroupData`, and scalar `ItemData` values
- Resolve item labels, data types, and controlled values from `ItemDef` and
  `CodeList` metadata
- Use stable `ItemOID` values as mapping keys without requiring a REDCap data
  dictionary
- Preserve group paths, sequence values, and repeat keys in provenance so
  repeated data cannot be overwritten silently
- Report unsupported multi-valued or ambiguous structures explicitly
- Produce BFF first and reuse the existing BFF-to-PXF and BFF-to-OMOP routes

### Architecture

- Split ODM parsing into explicit v1 and v2 adapters rather than adding
  version conditionals to `odm2redcap`
- Introduce a format-neutral field-metadata interface used by both the REDCap
  dictionary adapter and the ODM v2 metadata adapter
- Keep source parsing and normalization separate from semantic BFF mapping
- Reuse the route registry, source result, mapping, BFF, PXF, OMOP, CLI, module,
  Python, and HTTP(s) API infrastructure

### Initially out of scope

- ODM JSON serialization and the ODM REST API
- Complete study-design and workflow processing
- Transactional or incremental updates
- Queries, signatures, and complete audit-trail semantics
- Top-level operational datasets outside participant `ClinicalData`
- Multi-valued items until their lossless normalized representation is defined

### Tests and validation

- Add an attributed, schema-valid fixture from the official CDISC ODM examples
- Test namespace and version rejection, recursive groups, repeat keys,
  metadata and codelist resolution, and unsupported structures
- Validate fixtures against the official ODM v2 XML schema during development
- Validate generated BFF, PXF, and OMOP output with the existing external
  validators
- Describe the feature as experimental ODM v2.0 XML ClinicalData input rather
  than complete ODM v2 support

## 0.34: OpenClinica ODM v1 input profile

Support OpenClinica through the existing CDISC ODM input route rather than
introducing a separate format or CLI flag. OpenClinica exports CDISC ODM 1.3
with vendor extensions and uses the same subject, study-event, form,
item-group, and attribute-based item-value hierarchy already handled by the
ODM v1 parser. Mapping rules remain specific to the source document's
`ItemOID` values.

The preferred source is a CDISC ODM XML 1.3 Full export with OpenClinica
extensions because it includes both clinical data and study metadata. The
initial implementation should process snapshot clinical data while preserving
or reporting extension content that is not mapped semantically.

### Initial scope

- Continue using `-icdisc-odm` and the existing BFF, PXF, and OMOP output routes
- Detect the ODM version and OpenClinica extension namespace explicitly
- Support ODM 1.3 snapshot `ClinicalData` and its accompanying metadata
- Use `OpenClinica:StudySubjectID` when available while retaining `SubjectKey`
- Expose `StudyEventOID`, form and group identifiers, sequence values, and
  repeat keys to normalization and provenance
- Keep stable `ItemOID` values as source keys for project-specific mappings
- Resolve labels, data types, and controlled values from `MetaDataVersion`,
  `ItemDef`, and `CodeList` where available

### Required ODM v1 groundwork

- Normalize singleton and repeated XML elements consistently; `XML::Fast`
  represents singleton elements as hashes and repeated elements as arrays
- Replace the REDCap-specific event assumption with generic ODM event context
  while continuing to recognize `redcap:UniqueEventName`
- Preserve repeated item groups without allowing identical `ItemOID` values to
  overwrite one another before mapping
- Introduce the format-neutral field-metadata interface shared with the ODM v2
  work instead of requiring OpenClinica users to construct a REDCap dictionary
- Keep parsing, source normalization, metadata resolution, and BFF mapping as
  separate stages

### Initially out of scope

- Direct retrieval from the authenticated OpenClinica API
- A separate parser for the OpenClinica JSON API response
- Transactional ODM updates
- Semantic conversion of audit logs, discrepancy notes, signatures, and file
  attachments
- ODM 1.2 unless a representative use case and fixture require it

### Tests and validation

- Obtain an anonymized OpenClinica ODM XML 1.3 Full export with extensions and
  acknowledge its source in the fixture README
- Cover singleton elements, repeated events, repeated item groups, identifier
  selection, metadata and codelist resolution, and ignored extensions
- Ensure repeated item values cannot be lost or silently overwritten
- Validate generated BFF, PXF, and OMOP output with the existing external
  validators
- Describe the feature as an OpenClinica profile of CDISC ODM v1 rather than a
  new OpenClinica data format

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
