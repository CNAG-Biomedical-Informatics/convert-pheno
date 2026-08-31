---
title: Interface Availability
sidebar_label: Interface Availability
---

Format | CLI | Perl/Python module | Mojolicious HTTP(s) API
--- | --- | --- | ---
[Beacon v2 Models](../bff) | Recommended | Supported | Recommended
[cBioPortal clinical study](../cbioportal) | Supported; experimental profile | Supported; experimental profile | Supported as ZIP input
[CDISC Dataset-JSON](../dataset-json) | Supported; experimental profile | Supported; experimental profile | Supported as file input
[CDISC Dataset-XML](../dataset-xml) | Supported; experimental profile | Supported; experimental profile | Supported with Define-XML
[CDISC-ODM](../cdisc-odm) | Recommended | Supported | Supported as file input
[CSV](../csv) | Recommended | Supported | Supported with mapping file
[FHIR R4](../fhir) | Supported; experimental profile | Supported; experimental profile | Supported for JSON Bundles
[i2b2](../i2b2) | Supported; experimental profile | Supported; experimental profile | Supported as JSON or table package
[OMOP-CDM](../omop-cdm) | Recommended | Supported | Supported as JSON or table files
[OpenClinica ODM](../openclinica) | Supported; experimental profile | Supported; experimental profile | Supported as file input
[openEHR canonical](../openehr) | Supported; experimental profile | Supported; experimental profile | Supported for JSON or YAML compositions
[PCORnet CDM](../pcornet) | Supported; experimental profile | Supported; experimental profile | Supported as JSON or table package
[Phenopackets v2](../pxf) | Recommended | Supported | Recommended
[REDCap](../redcap) | Recommended | Supported | Supported with mapping and dictionary files
[Sentinel CDM](../sentinel) | Supported; experimental profile | Supported; experimental profile | Supported as JSON or table package

This table describes **interface suitability**, not conversion coverage. See [Supported Formats](../supported-formats) for the input/output map and [Choose a Conversion](../conversion-recipes) for commands.

The Mojolicious API supports self-contained JSON and registry-defined multipart
uploads. The JSON-only Python HTTP API does not expose file-oriented routes and
is planned for future deprecation. Use the CLI for streaming or large inputs.
