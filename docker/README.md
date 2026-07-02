# Docker

Containerized usage is recommended when you want a reproducible environment with Perl dependencies preinstalled.

## Method 1: From Docker Hub

Download the latest image from Docker Hub:

```bash
docker pull manuelrueda/convert-pheno:latest
docker image tag manuelrueda/convert-pheno:latest cnag/convert-pheno:latest
```

## Method 2: Build From Dockerfile

The repository includes a `docker/Dockerfile`.

Build the image locally with:

```bash
docker buildx build -t cnag/convert-pheno:latest .
```

## Run The Container

Start a detached container:

```bash
docker run -tid \
  -e USERNAME=root \
  --name convert-pheno \
  cnag/convert-pheno:latest
```

Enter the container:

```bash
docker exec -ti convert-pheno bash
```

The command-line executable is available at:

```text
/usr/share/convert-pheno/bin/convert-pheno
```

The default container user is `root`, but you can also run as `UID=1000` (`dockeruser`):

```bash
docker run --user 1000 -tid \
  --name convert-pheno \
  cnag/convert-pheno:latest
```

## Use `make`

If you prefer, use the included `makefile.docker`:

```bash
make -f makefile.docker install
make -f makefile.docker run
make -f makefile.docker enter
```

## Mount Volumes

Containers are isolated: files on your computer are not visible inside the
container unless you mount them. The easiest approach is to put the input files,
mapping files, dictionaries, optional databases, and output directory under one
project directory and mount that directory as `/data`.

Recommended layout on the host:

```text
my_convert_pheno_run/
|-- input/
|   |-- clinical.csv
|   |-- redcap.csv
|   `-- redcap-dictionary.csv
|-- mapping/
|   `-- mapping.yaml
|-- db/
|   `-- ohdsi.db
`-- output/
```

Start the container with that directory mounted:

```bash
docker run -tid \
  --volume "$PWD/my_convert_pheno_run:/data" \
  --name convert-pheno-mount \
  cnag/convert-pheno:latest
```

Then run commands using the container paths:

```bash
convert-pheno() {
  docker exec -ti convert-pheno-mount \
    /usr/share/convert-pheno/bin/convert-pheno "$@"
}

convert-pheno -icsv /data/input/clinical.csv \
  --mapping-file /data/mapping/mapping.yaml \
  --search-audit-tsv /data/output/search-audit.tsv \
  -obff /data/output/individuals.json
```

For REDCap input, keep both the export and dictionary under the mounted
directory:

```bash
convert-pheno -iredcap /data/input/redcap.csv \
  --redcap-dictionary /data/input/redcap-dictionary.csv \
  --mapping-file /data/mapping/mapping.yaml \
  -obff /data/output/individuals.json
```

If your files are already in different host directories, you do not need to copy
them. Mount each directory explicitly and use the container paths in the command:

```bash
docker run -tid \
  --volume /path/to/input:/input:ro \
  --volume /path/to/mapping:/mapping:ro \
  --volume /path/to/output:/output \
  --volume /path/to/db:/db:ro \
  --name convert-pheno-mount \
  cnag/convert-pheno:latest

docker exec -ti convert-pheno-mount /usr/share/convert-pheno/bin/convert-pheno \
  -icsv /input/clinical.csv \
  --mapping-file /mapping/mapping.yaml \
  --path-to-ohdsi-db /db \
  -obff /output/individuals.json
```

Use read-only mounts (`:ro`) for inputs, mappings, and databases when you do not
want the container to modify those files. Do not use `:ro` for output
directories.

## System Requirements

- Supported targets: `linux/amd64` and `linux/arm64`
- Perl 5.26+ inside the image
- At least 4 GB RAM
- At least 1 CPU core
- At least 16 GB disk space

## Optional Athena-OHDSI Database

If you need `--ohdsi-db`, download `ohdsi.db` separately and either place it
under `share/db/` in a local checkout or mount it into the container and point
to it with `--path-to-ohdsi-db`.

You can either download it manually in a browser from this Google Drive
directory:

- <https://drive.google.com/drive/folders/1-5Ywf-hhwb8bX1sRNV2Tf3EjH4TCaC8P?usp=sharing>

or download the file from the command line with `gdown`:

```bash
pip install gdown
```

```python
import gdown

url = "https://drive.google.com/uc?export=download&id=1zQ26Q1qsqTBPDGrtZbhDP-85NhaOrfBP"
output = "./ohdsi.db"
gdown.download(url, output, quiet=False)
```
