FROM ubuntu

# File Author / Maintainer
MAINTAINER Manuel Rueda <manuel.rueda@cnag.crg.eu>

# Install Linux tools
RUN apt-get update && \
    apt-get -y install gcc unzip make git cpanminus perl-doc vim sudo libxml-hash-lx-perl

# Download app
WORKDIR /usr/share/
RUN git clone https://github.com/mrueda/convert-pheno.git

# Install Perl modules
WORKDIR /usr/share/convert-pheno
RUN cpanm --sudo --installdeps .
