# Troubleshooting

This page collects a few issues that users have asked about more than once.

## CSV_XS separator error

If you see an error like:

```text
CSV_XS ERROR: 2023 - EIQ - QUO character not allowed @ rec 1 pos 21 field 1
```

the most common cause is a mismatch between the file separator and what `Convert-Pheno` expects from the file extension.

### What to check

- If the input is REDCap, make sure the data export and dictionary use the same separator.
- If the file is not using the default separator, pass it explicitly with `--sep`.

Example for a tab-separated file:

```bash
--sep $'\t'
```

## REDCap export mode

For REDCap input, the recommended export is:

- `CSV / Microsoft Excel (raw data)`

and the matching REDCap dictionary file should be included.

If your export uses labels instead of raw data, you can still work through the [CSV](csv.md) route instead of the `-iredcap` route.

## Python API / local bridge installation

The current Python support path shells out to a small Perl JSON bridge.

If you are installing the non-containerized version from source, check whether the system is missing:

- `perl`
- `cpanm`
- `python3-pip`

On Debian or Ubuntu systems, that usually means:

```bash
sudo apt-get install cpanminus python3-pip perl
```

If the Python API still fails, also verify that:

- `Convert::Pheno` and its Perl dependencies were installed successfully
- the repo-local helper exists at `api/perl/json_bridge.pl`
- the Python helper exists at `lib/convertpheno.py`
