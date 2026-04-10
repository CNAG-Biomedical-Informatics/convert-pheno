# Session Notes

## Current Head

- Latest commit from this session: `9e99cb8` (`Refactor CLI and shared module namespaces`)
- Later local work after those notes:
  - legacy `pxf2bff -obff FILE` now warns when input PXF contains biosamples
    while still preserving them under `info.phenopacket.biosamples`
  - `PXF` BFF mapping was split toward `Source::ToBFF::Entity`:
    - `Convert::Pheno::PXF::ToBFF`
    - `Convert::Pheno::PXF::ToBFF::Individuals`
    - `Convert::Pheno::PXF::ToBFF::Biosamples`
  - `OMOP` BFF mapping now follows the same shape for `individuals`:
    - `Convert::Pheno::OMOP::ToBFF`
    - `Convert::Pheno::OMOP::ToBFF::Individuals`
  - placeholder scaffold added for future OMOP biosamples work:
    - `Convert::Pheno::OMOP::ToBFF::Biosamples`
    - `run_omop_to_bundle` now honors requested bundle entities, but OMOP
      biosamples currently return an empty list until real `SPECIMEN` mapping
      is implemented
  - CLI help and Markdown docs were updated to explain:
    - legacy `-obff FILE` compatibility behavior
    - `--entities ... --out-dir ...`
    - `--out-entity entity=file`
  - `--entities` now uses space-separated values rather than comma-separated
    lists, for example:
    - `--entities individuals biosamples`

Uncommitted but staged at the time of this note:

- CI fix for `Convert::Pheno::IO::CSVHandler` circular loading
- shared `pxf.json` biosamples fixture/output update
- stricter BFF entity-mode CLI validation
- per-entity output filename overrides via `--out-entity entity=file`

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

The historical design pattern was:

1. Parse input format.
2. Map it into the internal Beacon-like center model.
3. Optionally map again into the final output format.

Important caveat, still true at the public API level:

- The “center model” is not a general Beacon bundle.
- In practice it is Beacon `individuals`.
- Data that belong to other Beacon entities, such as `biosamples`, are often
  retained under `info` rather than emitted as first-class entities.

Important caveat, now partially improved internally:

- A new internal `Context` + `Bundle` contract exists.
- OMOP and PXF can now build a bundle internally.
- Legacy public behavior still unwraps back to `individuals` by default.

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
  - Still dispatches into format-specific modules.
  - No longer carries as much OMOP-specific detail as before.
  - `array_dispatcher` now routes through `Convert::Pheno::Runner`.

- `lib/Convert/Pheno/Runner.pm`
  - New internal execution core.
  - Resolves operations as `legacy` vs `bundle`.
  - Compatibility layer during the refactor away from raw `method` dispatch.

- `lib/Convert/Pheno/CLI/Args.pm`
  - New extracted CLI argument parser / normalizer.
  - Owns generic `-i/-o` support, compact flag parsing, validation, and request
    construction.

- `lib/Convert/Pheno/Context.pm`
  - New internal execution context object.
  - Holds source/target/entity intent and execution resources.

- `lib/Convert/Pheno/Model/Bundle.pm`
  - New internal canonical bundle container.
  - Currently used for `individuals`, and for first-class PXF `biosamples`.

### Format converters

- `lib/Convert/Pheno/PXF.pm`
  - PXF -> Beacon `individuals`.
  - Also normalizes things like `medical_actions` -> `medicalActions`,
    `meta_data` -> `metaData`.
  - Preserves `biosamples`, `files`, `interpretations`, etc. in `info`.
  - New internal `run_pxf_to_bundle` path.
  - When `biosamples` are requested and present in the PXF input, they are also
    exposed as first-class bundle entities.
  - Current `biosamples` support is pass-through/extraction, not yet a true
    semantic PXF -> Beacon biosamples mapping.

- `lib/Convert/Pheno/BFF/ToPXF.pm`
  - Beacon `individuals` -> PXF.

- `lib/Convert/Pheno/OMOP.pm`
  - Now mostly a compatibility facade over the new OMOP submodules.

- `lib/Convert/Pheno/OMOP/Source.pm`
  - New OMOP input collection layer.
  - Detects SQL vs CSV and prepares OMOP source context.

- `lib/Convert/Pheno/OMOP/ParticipantStream.pm`
  - New OMOP participant/stream orchestration layer.
  - Owns more of the stream-vs-non-stream preparation behavior.

- `lib/Convert/Pheno/OMOP/Mapper/Individuals.pm`
  - New extracted OMOP participant -> `individuals` mapper.
  - Contains the moved OMOP mapping subs from the old monolithic `OMOP.pm`.

- `lib/Convert/Pheno/Emit/OMOP.pm`
  - New OMOP stream emission/serialization helper layer.

- `lib/Convert/Pheno/BFF/ToOMOP.pm`
  - Beacon `individuals` -> OMOP table rows.

- `lib/Convert/Pheno/CSV.pm`
  - CSV -> Beacon `individuals` using mapping configuration.

- `lib/Convert/Pheno/REDCap.pm`
  - REDCap -> Beacon `individuals` using mapping configuration and dictionary.

- `lib/Convert/Pheno/CDISC.pm`
  - CDISC-ODM -> Beacon `individuals` via an intermediate REDCap-like structure.

- `lib/Convert/Pheno/JSONLD.pm`
  - Beacon / PXF -> JSON-LD.

### I/O and preprocessing

- `lib/Convert/Pheno/IO/CSVHandler.pm`
  - CSV/TSV/SQL reading helpers.
  - OMOP SQL/CSV loading and stream processing.
  - Helpers for transposing OMOP row sets and building table indexes.
  - Also contains CSV writing and gzip-aware filehandle helpers.
  - Recent fix: gzip append handling for newly created stream output files.
  - Recent fix: removed a circular `use Convert::Pheno;` load that could cause
    GitHub CI import failures such as missing `read_csv` imports.

- `lib/Convert/Pheno/IO/FileIO.pm`
  - JSON/YAML read/write helpers.

### Mapping, defaults, DB lookup

- `lib/Convert/Pheno/Mapping/Shared.pm`
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

Current implemented state:

- PXF can emit bundle-level `biosamples` internally and through the CLI.
- CLI supports `--entities biosamples` for `-ipxf ... -obff`.
- The main regression fixture `t/pxf2bff/in/pxf.json` now contains biosamples
  and drives both:
  - `t/pxf2bff/out/individuals.json`
  - `t/pxf2bff/out/biosamples.json`
- The current PXF `biosamples` path is intentionally light-weight:
  it promotes/normalizes biosamples rather than performing a full semantic
  Beacon biosamples mapping.
- OMOP `SPECIMEN -> biosamples` is intentionally deferred until real specimen
  example data is available.

Recommended implementation order for that work:

1. Keep current behavior as default for backward compatibility.
2. Introduce canonical multi-entity bundle.
3. Add optional `biosamples` emission first for `pxf2bff`.
4. Add first-pass `SPECIMEN -> biosamples` mapping for `omop2bff`.
5. Add CLI/API support for selecting emitted entities.

## Current CLI Rules

The current CLI now supports both:

- compact syntax: `-ipxf ... -obff ...`
- generic syntax: `-i pxf ... -o bff ...`

Constructor cleanup:

- CLI and shared test helpers now omit absent optional values instead of
  passing lots of explicit `undef` values into `Convert::Pheno->new(...)`.

BFF output semantics:

- `-obff FILE`
  - single-output compatibility mode
  - effectively writes `individuals`
- `--entities ...`
  - switches BFF output into entity mode
  - writes one file per entity into `--out-dir` or `.` by default
- `--entities` together with `-obff FILE`
  - hard error
- custom entity filenames are supported with repeated:
  - `--out-entity entity=file`
  - example:
    - `--out-entity biosamples=samples.json`

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
- `t/17-context-bundle.t`
- `t/18-cli-entities.t`
- `t/19-cli-regression.t`
- `t/20-cli-stream-omop.t`

`xt/` was also cleaned up to be stylistically consistent with `t/`.

Current CLI regression coverage restored in `t/`:

- broad file-based CLI matrix:
  - `bff2pxf`
  - `pxf2bff`
  - `pxf2bff --entities biosamples`
  - `redcap2bff`
  - `redcap2pxf`
  - `omop2bff`
  - `omop2pxf`
  - `cdisc2bff`
  - `cdisc2pxf`
  - `bff2csv`
  - `bff2jsonf`
  - `pxf2csv`
  - `pxf2jsonf`
  - `csv2bff`
  - `csv2pxf`

- dedicated streamed OMOP CLI regressions:
  - SQL.gz with `DRUG_EXPOSURE`
  - CSV.gz with `PERSON`, `CONCEPT`, `DRUG_EXPOSURE`

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
- CLI absolute output paths are now preserved correctly in `bin/convert-pheno`
  instead of being incorrectly prefixed with `out_dir`.
- Streamed gzip output creation now works for new files in
  `lib/Convert/Pheno/IO/CSVHandler.pm`.
- Added comment in `lib/Convert/Pheno.pm` documenting that canonical JSON sorts
  keys lexicographically, so `id` will not always appear first in output rows.

Observed but not fully cleaned up:

- There is an unstaged local file named `Changes` in the repo root.
- There are several unrelated untracked local artifacts still present:
  `.codex`, `debug_windows-latest/`, `nytprof.readme`, some extra `t/` files,
  and a few helper scripts under `docs/tbl/`.
- The streamed plain non-gz OMOP CSV CLI path still looks suspicious and should
  be treated separately from the now-restored streamed CSV.gz regression.

- Several direct-module tests require preloading `JSON::PP` because some modules
  use `JSON::PP::true` / `JSON::PP::false` as barewords in ways that are brittle
  under direct compilation/import paths.

## Recommended Next Steps

If continuing after this session:

1. Decide whether to fix and regression-test the streamed plain CSV OMOP CLI
   path separately.
2. Keep moving legacy converter paths onto `Context` + `Bundle` + `Runner`.
3. Extend docs as needed, but keep CLI POD as the command source of truth.
4. When ready, define the next internal step for multi-entity output:
   - either carry bundle/entity intent deeper into emitters,
   - or start implementing a proper PXF biosamples mapping.
5. Do not implement OMOP biosamples until real `SPECIMEN` example data exists.

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
