FROM ubuntu:22.04
#FROM perl:5.36-bullseye # Build fails with PyPerler

# File Author / Maintainer
LABEL maintainer Manuel Rueda <manuel.rueda@cnag.eu>

# Install Linux tools
RUN apt-get update && \
    apt-get -y install gcc unzip make git cpanminus perl-doc vim sudo libbz2-dev zlib1g-dev libperl-dev libssl-dev python3-pip cython3 && \
    pip3 install setuptools "fastapi[all]"

# Download Convert-Pheno
WORKDIR /usr/share/
RUN git clone https://github.com/CNAG-Biomedical-Informatics/convert-pheno.git

# Remove the .git folder to save space and avoid shipping VCS data
RUN rm -rf convert-pheno/.git

# Install Perl modules
WORKDIR /usr/share/convert-pheno
RUN cpanm --notest --installdeps .

# Download and install PyPerler
WORKDIR share/ex
RUN git clone https://github.com/tkluck/pyperler.git
WORKDIR pyperler
RUN make install > install.log 2>&1

# Add user "dockeruser"
ARG UID=1000
ARG GID=1000

RUN groupadd -g "${GID}" dockeruser \
  && useradd --create-home --no-log-init -u "${UID}" -g "${GID}" dockeruser

# To change default user from root -> dockeruser
#USER dockeruser

# Get back to entry dir
WORKDIR /usr/share/convert-pheno
