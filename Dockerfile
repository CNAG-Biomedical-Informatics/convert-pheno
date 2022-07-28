FROM ubuntu

# File Author / Maintainer
MAINTAINER Manuel Rueda <manuel.rueda@cnag.crg.eu>

# Install Linux tools
RUN DEBIAN_FRONTEND=noninteractive apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install gcc make git cpanminus perl-doc vim sudo

# Download app
WORKDIR /usr/share/
RUN git clone https://github.com/mrueda/Convert-Pheno.git

# Install Perl modules
WORKDIR /usr/share/Convert-Pheno
RUN cpanm --sudo --installdeps .
