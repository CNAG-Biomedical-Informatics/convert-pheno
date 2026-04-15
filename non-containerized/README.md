# Non-Containerized Installation

Use this path when you want to run `convert-pheno` directly from CPAN, GitHub, or inside your own Perl environment.

## System Dependencies

On Debian-based distributions, install:

```bash
sudo apt-get install cpanminus libbz2-dev zlib1g-dev libperl-dev
```

Optional for development:

```bash
sudo apt-get install libssl-dev
```

`libssl-dev` is only needed for SSL-backed development features such as
`--self-validate-schema`. It is not required for normal conversions.

## Method 1: From CPAN

### Option 1: Install Under `~/perl5`

```bash
cpanm --local-lib=~/perl5 local::lib && eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)
cpanm --notest Convert::Pheno
convert-pheno --help
```

To make the local Perl library persistent across shells:

```bash
echo 'eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)' >> ~/.bashrc
```

To update later:

```bash
cpanm Convert::Pheno
```

## Method 2: CPAN In A Conda Environment

This path is useful when you want an isolated environment but still want to run the non-containerized CLI or Perl module.

### Step 1: Install Miniconda

The following example targets `x86_64` Linux systems:

```bash
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh
```

Close and reopen the terminal after the installer finishes.

### Step 2: Configure Channels

Set up the channels required by Bioconda:

```bash
conda config --add channels bioconda
```

It is better to install into a fresh environment to avoid dependency conflicts.

### Step 3: Create The Environment And Install

```bash
conda create -n myenv
conda activate myenv
conda install -c conda-forge gcc_linux-64 perl perl-app-cpanminus
# conda install -c bioconda perl-mac-systemdirectory   # macOS only
cpanm --notest Convert::Pheno
convert-pheno --help
```

Replace `myenv` with your preferred environment name.

To deactivate the environment:

```bash
conda deactivate
```

## Method 3: From GitHub

Clone the repository:

```bash
git clone https://github.com/cnag-biomedical-informatics/convert-pheno.git
cd convert-pheno
```

Update an existing clone:

```bash
git pull
```

### Option 1: Install Dependencies Under `~/perl5`

```bash
cpanm --local-lib=~/perl5 local::lib && eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)
cpanm --notest --installdeps .
bin/convert-pheno --help
```

Persist the local Perl library:

```bash
echo 'eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)' >> ~/.bashrc
```

## Athena-OHDSI Database

Some OMOP workflows need `ohdsi.db`.

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

Once downloaded, either:

1. Move `ohdsi.db` into `share/db/`.
2. Keep it elsewhere and pass `--path-to-ohdsi-db`.
