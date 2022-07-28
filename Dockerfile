##########################
## Build env
##########################

FROM ubuntu
RUN DEBIAN_FRONTEND=noninteractive apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install gcc make git cpanminus perl-doc vim sudo

##########################
## Clone applications
##########################

WORKDIR /usr/share/

RUN git clone https://github.com/mrueda/Convert-Pheno.git

WORKDIR /usr/share/Convert-Pheno

##########################
## Install Perl libraries
##########################

RUN cpanm --sudo --installdeps .
