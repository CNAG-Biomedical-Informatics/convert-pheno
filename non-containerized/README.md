# Non-Containerized Installation

Use this path when you want to run `convert-pheno` directly from CPAN, GitHub, or inside your own Perl environment.

## System Dependencies

On Debian-based distributions, install:

```bash
sudo apt-get install cpanminus libbz2-dev zlib1g-dev libperl-dev libssl-dev
```

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

### Optional: Use The Perl Module From Python

If you still want the legacy Python bridge inside the Conda environment, install `PyPerler` separately:

```bash
git clone https://github.com/tkluck/pyperler
cd pyperler
make install 2> install.log
```

After that, the example script installed with `Convert::Pheno` should be available under your Conda environment's Perl shared files.

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

Detailed download and placement instructions are documented in:

- <https://cnag-biomedical-informatics.github.io/convert-pheno/omop-cdm/>
- <https://cnag-biomedical-informatics.github.io/convert-pheno/download-and-installation/>
