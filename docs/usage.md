# Usage

This page collects a few **common `convert-pheno` command-line patterns**. For the flag reference, see [Use as a command-line interface](use-as-a-command-line-interface.md).

## Convert Phenopackets to BFF output

```bash
convert-pheno -ipxf pxf.json -obff individuals.json
```

Use this when your input is a **Phenopackets v2** file and you want `BFF` `individuals` output.

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

## Emit PXF biosamples when present

```bash
convert-pheno -ipxf pxf.json --entities biosamples --out-dir out/
```

This currently works when the `PXF` input contains **biosample data**. The output file will be written as `out/biosamples.json`.

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

## Work with repository fixtures

The repository test fixtures under `t/` are useful as **small examples**:

```bash
bin/convert-pheno -ipxf t/pxf2bff/in/pxf.json -obff individuals.json
bin/convert-pheno -ipxf t/pxf2bff/in/pxf.json --entities biosamples --out-dir out/
bin/convert-pheno -ipxf t/pxf2bff/in/pxf.json --entities individuals biosamples --out-dir out/ --out-entity biosamples=samples.json
bin/convert-pheno -iomop t/omop2bff/in/omop_cdm_eunomia.sql -opxf phenopackets.json
```

## Need more detail?

- [Supported formats](supported-formats.md)
- [Download & Installation](download-and-installation.md)
- [Use as a module](use-as-a-module.md)
- [Use as an API](use-as-an-api.md)
