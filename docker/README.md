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
docker run -tid -e USERNAME=root --name convert-pheno cnag/convert-pheno:latest
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
docker run --user 1000 -tid --name convert-pheno cnag/convert-pheno:latest
```

## Use `make`

If you prefer, use the included `makefile.docker`:

```bash
make -f makefile.docker install
make -f makefile.docker run
make -f makefile.docker enter
```

## Mount Volumes

Containers are isolated, so mount a host directory when you need to read or write local data:

```bash
docker run -tid --volume /media/mrueda/4TBT/data:/data --name convert-pheno-mount cnag/convert-pheno:latest
```

One convenient pattern is to create an alias on the host:

```bash
alias convert-pheno='docker exec -ti convert-pheno-mount /usr/share/convert-pheno/bin/convert-pheno'
convert-pheno -ibff /data/individuals.json -opxf pxf.json --out-dir /data
```

## System Requirements

- Supported targets: `linux/amd64` and `linux/arm64`
- Perl 5.26+ inside the image
- At least 4 GB RAM
- At least 1 CPU core
- At least 16 GB disk space
