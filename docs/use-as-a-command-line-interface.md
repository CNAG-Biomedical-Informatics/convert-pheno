`Convert-Pheno` includes a **command-line utility** for file-based conversions. This is the **primary way** most users work with the project.

[See common usage](usage.md){ .md-button .md-button--primary }
[Read the tutorial](tutorial.md){ .md-button }
[Check installation](download-and-installation.md){ .md-button }

## Basic pattern

The command is organized around **one input format** and **one output format**:

```bash
convert-pheno -i <input-type> <infile> -o <output-type> <outfile> [options]
```

Both CLI styles are supported:

- **Generic form:** `-i pxf ... -o bff ...`
- **Compact form:** `-ipxf ... -obff ...`

The compact flags are still the ones most users rely on:

- `-ipxf`, `-ibff`, `-iomop`, `-iredcap`, `-icdisc`, `-icsv`
- `-obff`, `-opxf`, `-oomop`, `-ocsv`, `-ojsonf`, `-ojsonld`

You can always check the current built-in help with:

```bash
convert-pheno --help
```

## BFF output modes

`BFF` output has two explicit CLI forms:

- `individuals`-only BFF output: `-obff FILE`
- Entity-aware output: `-obff --entities ... --out-dir DIR`

In other words, `--entities` does not replace `-obff`. It refines which `BFF` entities are written after you have already selected `BFF` as the output format.

## Common examples

Convert Phenopackets to the `individuals`-only `BFF` output:

```bash
convert-pheno -ipxf pxf.json -obff individuals.json
```

The same conversion with the generic form:

```bash
convert-pheno -i pxf pxf.json -o bff individuals.json
```

Convert Phenopackets to entity-aware `BFF` output:

```bash
convert-pheno -ipxf pxf.json -obff --entities individuals biosamples datasets cohorts --out-dir out/
```

Convert a mapping-file workflow to `individuals`, `datasets`, and `cohorts`:

```bash
convert-pheno -icsv data.csv --mapping-file mapping.yaml -obff --entities individuals datasets cohorts --out-dir out/
```

Convert both `individuals` and `biosamples`, while overriding the biosample filename:

```bash
convert-pheno -ipxf pxf.json -obff --entities individuals biosamples --out-dir out/ --out-name biosamples=samples.json
```

Convert a **large OMOP SQL dump** incrementally:

```bash
convert-pheno -iomop omop.sql.gz -obff individuals.json.gz --stream --ohdsi-db
```

Write a TSV audit of ontology lookups during a mapping-file conversion:

```bash
convert-pheno -icsv data.csv --mapping-file mapping.yaml -obff individuals.json --search-audit-tsv search-audit.tsv
```

Convert `BFF` `individuals` to Phenopackets:

```bash
convert-pheno -ibff individuals.json -opxf pxf.json
```

Convert `BFF` `individuals` to Phenopackets while changing the fallback `subject.vitalStatus` used when no source value is available:

```bash
convert-pheno -ibff individuals.json -opxf pxf.json --default-vital-status UNKNOWN_STATUS
```

## Notes

- `-obff` keeps the **individuals-only `BFF` behavior**.
- `BFF` entity mode is also explicit: use `-obff --entities ... --out-dir DIR`.
- When `PXF` input contains `biosamples`, the individuals-only `-obff FILE` path still writes only `individuals`. In that mode, `convert-pheno` warns and preserves the biosamples under `info.phenopacket.biosamples`.
- `--entities` can be used with `BFF` output. The supported output entities are `individuals`, `biosamples`, `datasets`, and `cohorts`.
- `biosamples` are currently emitted as first-class output from `-ipxf` input when biosample data is present.
- `datasets` and `cohorts` are synthesized from the normalized `individuals` collection.
- In mapping-file workflows, the top-level `beacon` section can override metadata for synthesized `datasets` and `cohorts`.
- This mapping-based augmentation is currently available only for `csv2bff`, `redcap2bff`, and `cdisc2bff`, which are the routes that use a mapping file.
- `--entities` narrows `BFF` output. It must be combined with `-obff` and `--out-dir`.
- `--out-name key=file` lets you override one multi-file output name. Use entity keys for `BFF` entity mode and table keys for `OMOP` output.
- `--search-audit-tsv FILE` writes a tab-separated audit of ontology search results for mapping-file-driven conversions such as `csv2bff`, `redcap2bff`, and `cdisc2bff`, including the effective configured search mode, whether each lookup matched the DB or fell back to `NA`, and the per-row lookup resolution (`exact`, `similarity`, or `fallback_na`).
- `--stream` is mainly relevant for **large OMOP inputs**.

## Important options

### Mapping-file conversions

- `--mapping-file FILE` supplies the YAML or JSON mapping file used by `csv2bff`, `redcap2bff`, `cdisc2bff`, and related conversions.
- `--redcap-dictionary FILE` or `-rcd FILE` supplies the REDCap data dictionary required by REDCap and CDISC input workflows.
- `--schema-file FILE` lets you validate mapping files against an alternative JSON Schema.
- `--self-validate-schema` or `-svs` performs a self-validation of the mapping schema itself. This is mainly an author or development check and may require SSL support in the Perl environment.
- `--search-audit-tsv FILE` writes a TSV report of ontology lookups performed during mapping-file-driven conversions.
  The audit includes both row-level results and the effective search settings used for the run.
- `--print-hidden-labels` or `-phl` preserves original text labels before ontology mapping in `_label` fields.

### Ontology search tuning

- `--search exact|mixed|fuzzy` selects the ontology lookup strategy. Default: `exact`.
- `--text-similarity-method cosine|dice` selects the token-similarity method used by `mixed` and `fuzzy`. Default: `cosine`.
- `--min-text-similarity-score FLOAT` sets the minimum score accepted by `mixed` and `fuzzy`. Default: `0.8`.
- `--levenshtein-weight FLOAT` sets the normalized Levenshtein weight used by `fuzzy`. Default: `0.1`.

For the search behavior itself, including examples and threshold tradeoffs, see [the DB search explainer](tbl/db-search.md).

### OMOP-specific options

- `--ohdsi-db` enables Athena-OHDSI lookup when OMOP data needs concepts not already present in the local export.
- `--path-to-ohdsi-db DIR` points to the directory containing `ohdsi.db`.
- `--omop-tables TABLE ...` restricts which OMOP-CDM tables are processed, while `CONCEPT` and `PERSON` stay included.
- `--exposures-file FILE` provides a CSV list of OMOP `concept_id` values to be treated as exposures.
- `--stream` enables incremental OMOP processing for individuals-only `-obff` output.
- `--sql2csv` prints SQL tables instead of converting them.
- `--max-lines-sql N` limits how many lines are read per SQL table. Default: `500`.

### General options

- `--separator CHAR` or `--sep CHAR` overrides the CSV delimiter. For `.csv` files the default remains `;`.
- `--username NAME` or `-u NAME` overrides the username stored in conversion metadata.
- `--default-vital-status ALIVE|DECEASED|UNKNOWN_STATUS` sets the fallback `subject.vitalStatus.status` used for `PXF` output when no source-derived value is available. Default: `ALIVE`.
- `--test` suppresses time-varying metadata so generated files are stable for comparisons.
- `--verbose` or `-v` prints progress information.
- `--debug LEVEL` prints the resolved internal request and extra debugging output.
  With `LEVEL >= 2`, it also prints a compact SQLite lookup summary
  (requests, cache hits, DB lookups, search resolution, and SQL timings).

## More help

- [Usage](usage.md) for more examples
- [Download & Installation](download-and-installation.md) for setup
- [Google Colab tutorial](https://colab.research.google.com/drive/1T6F3bLwfZyiYKD6fl1CIxs9vG068RHQ6) if you want a disposable environment
