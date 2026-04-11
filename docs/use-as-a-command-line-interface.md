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

## Common examples

Convert Phenopackets to `BFF` `individuals` output:

```bash
convert-pheno -ipxf pxf.json -obff individuals.json
```

The same conversion with the generic form:

```bash
convert-pheno -i pxf pxf.json -o bff individuals.json
```

Convert Phenopackets biosamples when the input contains them:

```bash
convert-pheno -ipxf pxf.json --entities biosamples --out-dir out/
```

Convert both `individuals` and `biosamples`, while overriding the biosample filename:

```bash
convert-pheno -ipxf pxf.json --entities individuals biosamples --out-dir out/ --out-entity biosamples=samples.json
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

## Notes

- `-obff` keeps the **legacy `BFF` behavior**. By default this means `individuals`.
- When `PXF` input contains `biosamples`, the legacy `-obff FILE` path still writes only `individuals`. In that mode, `convert-pheno` warns and preserves the biosamples under `info.phenopacket.biosamples`.
- `--entities` can be used with `BFF` output. The current extra entity exposed by the CLI is `biosamples` from `-ipxf` input when biosample data is present.
- `--entities` is an entity-output mode. Use it together with `--out-dir`, not with `-obff FILE`.
- `--out-entity entity=file` lets you override the filename of one requested entity and requires `--entities`.
- `--search-audit-tsv FILE` writes a tab-separated audit of ontology search results for mapping-file-driven conversions such as `csv2bff`, `redcap2bff`, and `cdisc2bff`.
- `--stream` is mainly relevant for **large OMOP inputs**.

## More help

- [Usage](usage.md) for more examples
- [Download & Installation](download-and-installation.md) for setup
- [Google Colab tutorial](https://colab.research.google.com/drive/1T6F3bLwfZyiYKD6fl1CIxs9vG068RHQ6) if you want a disposable environment
