`Convert-Pheno` includes a **command-line utility** for file-based conversions. This is the **primary way** most users work with the project.

## Basic pattern

The command is organized around **one input format** and **one output format**:

```bash
convert-pheno [-i input-type] <infile> [-o output-type] <outfile> [options]
```

The compact flags are the ones most users rely on:

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

Convert Phenopackets biosamples when the input contains them:

```bash
convert-pheno -ipxf pxf.json --entities biosamples --out-dir out/
```

Convert a **large OMOP SQL dump** incrementally:

```bash
convert-pheno -iomop omop.sql.gz -obff individuals.json.gz --stream --ohdsi-db
```

Convert `BFF` `individuals` to Phenopackets:

```bash
convert-pheno -ibff individuals.json -opxf pxf.json
```

## Notes

- `-obff` keeps the **legacy `BFF` behavior**. By default this means `individuals`.
- `--entities` can be used with `BFF` output. The current extra entity exposed by the CLI is `biosamples` from `-ipxf` input when biosample data is present.
- `--stream` is mainly relevant for **large OMOP inputs**.

## More help

- [Usage](usage.md) for more examples
- [Download & Installation](download-and-installation.md) for setup
- [Google Colab tutorial](https://colab.research.google.com/drive/1T6F3bLwfZyiYKD6fl1CIxs9vG068RHQ6) if you want a disposable environment
