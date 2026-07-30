---
title: Interface Availability
sidebar_label: Interface Availability
---

Format | CLI | Perl/Python module | HTTP(s) API
--- | --- | --- | ---
[Beacon v2 Models](../bff) | Recommended | Supported | Recommended
[Phenopackets v2](../pxf) | Recommended | Supported | Recommended
[OMOP-CDM](../omop-cdm) | Recommended | Supported | Supported with care for self-contained requests
[openEHR canonical](../openehr) | Supported; experimental profile | Supported; experimental profile | Supported with care for self-contained requests
[CSV](../csv) | Recommended | Supported | Not recommended
[REDCap](../redcap) | Recommended | Supported | Not recommended
[CDISC-ODM](../cdisc-odm) | Recommended | Supported | Not recommended
[CDISC Dataset-JSON](../dataset-json) | Supported; experimental profile | Supported; experimental profile | Not available

This table describes **interface suitability**, not conversion coverage. See [Supported Formats](../supported-formats) for the input/output map and [Choose a Conversion](../conversion-recipes) for commands.

The HTTP(s) API is intended primarily for self-contained payloads. Mapping-file-based conversions such as CSV, REDCap, and CDISC-ODM depend on additional files and are therefore better handled through the CLI. Dataset-JSON accepts in-memory documents through the module, but its multi-file CLI route is not exposed through the HTTP(s) API.
