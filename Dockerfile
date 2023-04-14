FROM ubuntu
#FROM perl:5.36-bullseye # Build fails with PyPerler

# File Author / Maintainer
MAINTAINER Manuel Rueda <manuel.rueda@cnag.crg.eu>

# Install Linux tools
RUN apt-get update && \
    apt-get -y install gcc unzip make git cpanminus perl-doc vim sudo libbz2-dev zlib1g-dev libperl-dev libssl-dev python3-pip && \
    pip3 install setuptools "fastapi[all]"

# Download Convert-Pheno
WORKDIR /usr/share/
RUN git clone https://github.com/CNAG-Biomedical-Informatics/convert-pheno.git

# Install Perl modules
WORKDIR /usr/share/convert-pheno
RUN cpanm --installdeps .

# Install PyPerler
WORKDIR ex/pyperler
RUN make install 2> install.log

# Add user "dockeruser"
ARG UID=1000
ARG GID=1000

RUN groupadd -g "${GID}" dockeruser \
  && useradd --create-home --no-log-init -u "${UID}" -g "${GID}" dockeruser

# To change default user from root -> dockeruser
#USER dockeruser

# Get back to entry dir
WORKDIR /usr/share/convert-pheno
