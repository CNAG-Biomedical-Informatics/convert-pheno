FROM ubuntu
#FROM perl:5.36-bullseye # Build fails with PyPerler

# File Author / Maintainer
MAINTAINER Manuel Rueda <manuel.rueda@cnag.crg.eu>

# Install Linux tools
RUN apt-get update && \
    apt-get -y install gcc unzip make git cpanminus perl-doc vim sudo libperl-dev python3-pip && \
    pip3 install setuptools

# Download Convert-Pheno
WORKDIR /usr/share/
RUN git clone https://github.com/mrueda/convert-pheno.git

# Install Perl modules
WORKDIR /usr/share/convert-pheno
RUN cpanm --installdeps .

# Install PyPerler
WORKDIR ex/pyperler
RUN make install 2> install.log

# Get back to entry dir
WORKDIR /usr/share/convert-pheno
