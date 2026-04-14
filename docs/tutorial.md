This page gives **short, practical walkthroughs** for three common `convert-pheno` workflows.

!!! Tip "Google Colab version"
    A runnable notebook version is available in [Google Colab](https://colab.research.google.com/drive/1T6F3bLwfZyiYKD6fl1CIxs9vG068RHQ6). A local copy is also available in the [repo](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/nb/convert_pheno_cli_tutorial.ipynb).

!!! Note "Before you start"
    These examples assume that `Convert-Pheno` is already installed. If not, start with [Download & Installation](download-and-installation.md).

## REDCap to PXF

This is a good route when you have a **REDCap export** and want to produce **Phenopackets**.

You will usually need three files:

1. REDCap data export in CSV format
2. REDCap data dictionary in CSV format
3. Mapping file in YAML or JSON format

Because REDCap projects are **free-form**, the mapping file is what tells `Convert-Pheno` how your project variables should be interpreted.

--8<-- "tbl/mapping-file.md"

For **mapping-file-based conversions**, `Convert-Pheno` can also use similarity-based lookup to help connect source fields to target terms:

--8<-- "tbl/db-search.md"

Run the conversion:

```bash
convert-pheno -iredcap redcap.csv \
  --redcap-dictionary dictionary.csv \
  --mapping-file mapping.yaml \
  -opxf phenopackets.json
```

If you need more detail about REDCap-specific behavior, see [REDCap](redcap.md).

## OMOP CDM to BFF

This route is meant for **OMOP exports** in SQL or CSV form.

Two situations are common:

1. Full export: the `CONCEPT` table already contains the standardized terms needed for conversion
2. Partial export: some terms are missing, so `Convert-Pheno` needs the bundled ATHENA-OHDSI lookup database and the `--ohdsi-db` flag

For smaller inputs:

```bash
convert-pheno -iomop omop.sql -obff individuals.json
```

For larger inputs:

```bash
convert-pheno -iomop omop.sql.gz -obff individuals.json.gz --stream --ohdsi-db
```

If you are working with OMOP regularly, see [OMOP-CDM](omop-cdm.md) for the fuller explanation of SQL, CSV, `CONCEPT`, and streaming behavior.

If you want entity-aware `BFF` output instead of the legacy single-file `individuals.json` path, request the entities explicitly:

```bash
convert-pheno -iomop PERSON.csv CONCEPT.csv DRUG_EXPOSURE.csv \
  --entities individuals datasets cohorts \
  --out-dir out/
```

In mapping-file workflows, the top-level `beacon` section can override synthesized `datasets` and `cohorts` metadata.

## CSV to BFF

This route is intended for **raw clinical CSV data** that does not already follow one of the supported data models.

As with REDCap, the **key requirement** is a mapping file that connects your CSV fields to terms understood by `Convert-Pheno`.

--8<-- "tbl/mapping-file.md"

The same similarity-based lookup used with REDCap mappings can also help when building CSV mappings:

--8<-- "tbl/db-search.md"

Run the conversion:

```bash
convert-pheno -icsv clinical_data.csv \
  --mapping-file clinical_data_mapping.yaml \
  -obff individuals.json
```

If your separator is not the default one expected by the tool, add `--sep`.

If you want `datasets` and `cohorts` as well, switch to entity mode:

```bash
convert-pheno -icsv clinical_data.csv \
  --mapping-file clinical_data_mapping.yaml \
  --entities individuals datasets cohorts \
  --out-dir out/
```

## Need more detail?

- [Usage](usage.md) for more command examples
- [CSV](csv.md) for raw CSV input
- [REDCap](redcap.md) for REDCap exports
- [OMOP-CDM](omop-cdm.md) for OMOP-specific options and caveats
- [FAQ](faq.md) for common questions
