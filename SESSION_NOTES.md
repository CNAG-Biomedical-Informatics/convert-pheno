# Session Notes

## What The Code Does

`Convert-Pheno` interconverts several clinical/phenotypic data formats.

Supported practical flows in this repo include:

- PXF <-> Beacon-flavored JSON (`individuals`)
- REDCap -> Beacon / PXF
- CSV -> Beacon / PXF / OMOP
- CDISC-ODM -> Beacon / PXF / OMOP
- OMOP -> Beacon / PXF
- Beacon -> OMOP
- Beacon / PXF -> CSV / JSON flattening / JSON-LD

The main current design pattern is:

1. Parse input format.
2. Map it into the internal Beacon-like center model.
3. Optionally map again into the final output format.

Important caveat:

- The “center model” is not a general Beacon bundle.
- In practice it is Beacon `individuals`.
- Data that belong to other Beacon entities, such as `biosamples`, are often
  retained under `info` rather than emitted as first-class entities.

## How The Code Is Organized

### Main entry points

- `bin/convert-pheno`
  - CLI entry point.
  - Parses flags, builds a `Convert::Pheno` object, runs the selected method,
    writes output files.

- `lib/Convert/Pheno.pm`
  - Main orchestrator class.
  - Holds object attributes via `Moo`.
  - Exposes methods such as `omop2bff`, `pxf2bff`, `csv2pxf`, `bff2omop`, etc.
  - Dispatches into format-specific modules.
  - Contains important wrapper/orchestration logic, especially OMOP pipeline and
    stream-vs-non-stream behavior.

### Format converters

- `lib/Convert/Pheno/PXF.pm`
  - PXF -> Beacon `individuals`.
  - Also normalizes things like `medical_actions` -> `medicalActions`,
    `meta_data` -> `metaData`.
  - Preserves `biosamples`, `files`, `interpretations`, etc. in `info`.

- `lib/Convert/Pheno/Bff2Pxf.pm`
  - Beacon `individuals` -> PXF.

- `lib/Convert/Pheno/OMOP.pm`
  - OMOP -> Beacon `individuals`.
  - Maps tables such as `PERSON`, `OBSERVATION`, `MEASUREMENT`,
    `CONDITION_OCCURRENCE`, `PROCEDURE_OCCURRENCE`, `DRUG_EXPOSURE`.
  - Handles stream duplicate suppression.

- `lib/Convert/Pheno/Bff2Omop.pm`
  - Beacon `individuals` -> OMOP table rows.

- `lib/Convert/Pheno/CSV.pm`
  - CSV -> Beacon `individuals` using mapping configuration.

- `lib/Convert/Pheno/REDCap.pm`
  - REDCap -> Beacon `individuals` using mapping configuration and dictionary.

- `lib/Convert/Pheno/CDISC.pm`
  - CDISC-ODM -> Beacon `individuals` via an intermediate REDCap-like structure.

- `lib/Convert/Pheno/RDF.pm`
  - Beacon / PXF -> JSON-LD.

### I/O and preprocessing

- `lib/Convert/Pheno/IO/CSVHandler.pm`
  - CSV/TSV/SQL reading helpers.
  - OMOP SQL/CSV loading and stream processing.
  - Helpers for transposing OMOP row sets and building table indexes.
  - Also contains CSV writing and gzip-aware filehandle helpers.

- `lib/Convert/Pheno/IO/FileIO.pm`
  - JSON/YAML read/write helpers.

### Mapping, defaults, DB lookup

- `lib/Convert/Pheno/Utils/Mapping.pm`
  - Shared mapping utilities.
  - Date/age conversions, ontology mapping helpers, format validation, OMOP
    table merging, misc shared conversions.

- `lib/Convert/Pheno/Utils/Default.pm`
  - Central default objects and values.

- `lib/Convert/Pheno/Utils/Schema.pm`
  - JSON schema validation for mapping files.

- `lib/Convert/Pheno/DB/SQLite.pm`
  - SQLite lookup layer for ontologies and OHDSI concepts.

- `lib/Convert/Pheno/DB/Similarity.pm`
  - Token/Levenshtein similarity helpers used for fuzzy matching.

- `lib/Convert/Pheno/OMOP/Definitions.pm`
  - OMOP constants: table names, headers, stream-memory tables, etc.

### APIs and docs

- `api/perl/`
  - Mojolicious-based simple API wrapper.

- `api/python/`
  - FastAPI-based wrapper around the Perl library.

- `docs/`
  - User/developer docs, mappings, format notes, roadmap, architecture notes.

- `t/`
  - Active test suite used in this session.

- `xt/`
  - Extended / optional / more environment-dependent tests.

## Context

This repository is a Perl tool to interconvert clinical/phenotypic data models.
The current internal center model is effectively Beacon v2 `individuals`, even
when source formats contain data that would fit other Beacon entities such as
`biosamples`.

Main architectural conclusion from this session:

- Do not rewrite in Python now.
- Keep Perl.
- Refactor the architecture, not the language.
- The biggest design issue is that the internal model is too tightly coupled to
  Beacon `individuals`.

Recommended future architectural direction:

- Introduce an entity-aware internal canonical bundle, e.g.

```json
{
  "individuals": [...],
  "biosamples": [...]
}
```

- Then map:
  - OMOP -> canonical bundle
  - PXF -> canonical bundle
  - REDCap / CSV / CDISC -> canonical bundle
  - canonical bundle -> Beacon entities / PXF / OMOP

## Biosamples Discussion

Feasibility assessment:

- PXF already preserves `biosamples`, but currently stores them under
  `individual.info.phenopacket.biosamples`.
- OMOP defines `SPECIMEN`, but it is not part of the active transform path.
- Emitting Beacon `biosamples` is feasible, but doing it cleanly requires
  refactoring away from the current `individuals`-centric internal model.

Recommended implementation order for that work:

1. Keep current behavior as default for backward compatibility.
2. Introduce canonical multi-entity bundle.
3. Add optional `biosamples` emission first for `pxf2bff`.
4. Add first-pass `SPECIMEN -> biosamples` mapping for `omop2bff`.
5. Add CLI/API support for selecting emitted entities.

## Test Suite Reorganization

The active `t/` suite was reorganized into smaller files with shared helpers.

Added helper:

- `t/lib/Test/ConvertPheno.pm`

Current active test files:

- `t/00-load.t`
- `t/01-api-bff-pxf.t`
- `t/02-api-tabular.t`
- `t/03-api-omop.t`
- `t/04-api-stream-omop.t`
- `t/05-errors.t`
- `t/06-mapping-errors.t`
- `t/07-api-bff-omop.t`
- `t/08-jsonld.t`
- `t/09-pxf-behavior.t`
- `t/10-bff2omop-behavior.t`
- `t/11-mapping-utils.t`
- `t/12-db-similarity.t`
- `t/13-db-sqlite.t`
- `t/14-csvhandler-utils.t`
- `t/15-convertpheno-orchestration.t`
- `t/16-omop-behavior.t`

`xt/` was also cleaned up to be stylistically consistent with `t/`.

## Coverage Status

We used `Devel::Cover`.

Command used:

```bash
cover -delete && HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lr t >/tmp/convert-pheno-cover.out && cover -summary
```

Latest active-`t/` coverage summary at end of session:

- statement: `95.6%`
- branch: `75.6%`
- condition: `61.6%`
- subroutine: `96.2%`
- overall total: `90.8%`

Important clarification:

- If the target is statement coverage, the project is already above `95%`.
- If the target is Devel::Cover overall total, it is not yet at `95%`.

Main remaining low/medium modules:

- `lib/Convert/Pheno.pm` -> `87.9%`
- `lib/Convert/Pheno/IO/CSVHandler.pm` -> `83.9%`
- `lib/Convert/Pheno/Utils/Mapping.pm` -> `83.8%`
- `lib/Convert/Pheno/RDF.pm` -> `89.8%`

The coverage grind beyond this point is still possible, but no longer cheap.

## Bugs / Technical Findings

Fixed in this session:

- `Utils::Mapping::string2number` now correctly loads `Math::BigInt`.

Observed but not fully cleaned up:

- There is still a runtime warning during `t/13-db-sqlite.t`:
  `Use of uninitialized value in subroutine entry at lib/Convert/Pheno/DB/SQLite.pm line 95.`
  It does not fail tests, but is worth cleaning later.

- Several direct-module tests require preloading `JSON::PP` because some modules
  use `JSON::PP::true` / `JSON::PP::false` as barewords in ways that are brittle
  under direct compilation/import paths.

## Recommended Next Steps

If continuing with testing before refactor:

1. Decide whether `95%` means statement coverage or overall Devel::Cover total.
2. If overall total is still desired, focus next on:
   - `Convert::Pheno.pm`
   - `IO::CSVHandler.pm`
   - `Utils::Mapping.pm`
   - remaining branch-heavy RDF/helper paths

If starting refactor now:

1. Preserve current CLI/API behavior.
2. Introduce internal canonical multi-entity bundle.
3. Decouple parsing, mapping, and emission layers.
4. Treat streaming as first-class infrastructure, not a special OMOP mode.
5. Begin with `PXF` and `OMOP` adapters because they matter most for
   future `biosamples`.

## Useful Commands

Run active suite:

```bash
prove -lr t
```

Run active + extended:

```bash
prove -lr t xt
```

Coverage:

```bash
cover -delete
HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lr t
cover -summary
```

## Final State

The repo is in a good state to start the architectural refactor.
The test suite is much stronger than at session start, and the design direction
for multi-entity support is clear.
