# Usage

This page collects a few **common `convert-pheno` command-line patterns**. For the flag reference, see [Use as a command-line interface](use-as-a-command-line-interface.md).

## Convert Phenopackets to legacy single-file BFF output

```bash
convert-pheno -ipxf pxf.json -obff individuals.json
```

Use this when your input is a **Phenopackets v2** file and you want the legacy single-file `BFF` `individuals` output.

## Convert BFF output to Phenopackets

```bash
convert-pheno -ibff individuals.json -opxf pxf.json
```

Use this when your starting point is a `BFF` `individuals` file.

## Convert OMOP SQL to BFF output

For smaller inputs:

```bash
convert-pheno -iomop omop.sql -obff individuals.json
```

For **larger inputs**, the streaming mode is usually more practical:

```bash
convert-pheno -iomop omop.sql.gz -obff individuals.json.gz --stream --ohdsi-db
```

!!! Note "OMOP streaming"
    `--stream` is mainly intended for large OMOP exports. The legacy `-iomop ... -obff` path still emits `individuals` by default.

## Emit multi-entity BFF output

```bash
convert-pheno -ipxf pxf.json --entities biosamples --out-dir out/
```

This currently works when the `PXF` input contains **biosample data**. The output file will be written as `out/biosamples.json`.

You can also request synthesized `datasets` and `cohorts`:

```bash
convert-pheno -icsv clinical_data.csv --mapping-file clinical_data_mapping.yaml --entities individuals datasets cohorts --out-dir out/
```

`datasets` and `cohorts` are synthesized from the normalized `individuals` collection, so they are available from BFF conversion routes beyond `PXF`. In mapping-file workflows, the top-level `beacon` section can override metadata such as `id`, `name`, `description`, `version`, or `cohortType`.

If you want both `individuals` and `biosamples`:

```bash
convert-pheno -ipxf pxf.json --entities individuals biosamples --out-dir out/
```

If you want a custom biosample filename:

```bash
convert-pheno -ipxf pxf.json --entities individuals biosamples --out-dir out/ --out-entity biosamples=samples.json
```

!!! Note "Legacy `-obff FILE` behavior"
    `convert-pheno -ipxf pxf.json -obff individuals.json` keeps the backward-compatible single-output path and emits only `individuals`. If the input also contains `biosamples`, the CLI prints a warning and preserves them under `info.phenopacket.biosamples`.

## Review ontology search results in mapping-file conversions

When using a mapping file, you can ask `convert-pheno` to write a TSV audit of ontology lookups:

```bash
convert-pheno -iredcap redcap.csv --redcap-dictionary dictionary.csv --mapping-file mapping.yaml -obff individuals.json --search-audit-tsv search-audit.tsv
```

This is useful when you want to review how original source terms were mapped to ontology labels and identifiers.
The audit also records the effective search configuration for the run, whether each lookup produced a real database match or fell back to `NA`, and whether the result came from exact matching, similarity search, or fallback.

## Work with repository fixtures

The repository test fixtures under `t/` are useful as **small examples**:

```bash
bin/convert-pheno -ipxf t/pxf2bff/in/pxf.json -obff individuals.json
bin/convert-pheno -ipxf t/pxf2bff/in/pxf.json --entities biosamples --out-dir out/
bin/convert-pheno -ipxf t/pxf2bff/in/pxf.json --entities individuals biosamples --out-dir out/ --out-entity biosamples=samples.json
bin/convert-pheno -icsv t/csv2bff/in/csv_data.csv --mapping-file t/csv2bff/in/csv_mapping.yaml --entities individuals datasets cohorts --out-dir out/
bin/convert-pheno -iomop t/omop2bff/in/omop_cdm_eunomia.sql -opxf phenopackets.json
```

## Need more detail?

- [Supported formats](supported-formats.md)
- [Download & Installation](download-and-installation.md)
- [Use as a module](use-as-a-module.md)
- [Use as an API](use-as-an-api.md)
