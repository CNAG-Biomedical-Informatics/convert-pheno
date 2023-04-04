FROM ubuntu
#FROM perl:5.36-bullseye # Build fails with PyPerler

# File Author / Maintainer
MAINTAINER Manuel Rueda <manuel.rueda@cnag.crg.eu>

#######################
# Install Linux tools #
#######################

RUN apt-get update && \
    apt-get -y install gcc unzip make git cpanminus perl-doc vim sudo libbz2-dev zlib1g-dev libperl-dev libssl-dev python3-pip gnupg2 && \
    pip3 install setuptools "fastapi[all]"

###############
# Install C-P #
###############

# Download Convert-Pheno
WORKDIR /usr/share/
RUN git clone https://github.com/mrueda/convert-pheno.git

# Install Perl modules
WORKDIR /usr/share/convert-pheno
RUN cpanm --installdeps .

# Install PyPerler
WORKDIR ex/pyperler
RUN make install 2> install.log

#############
# Install R #
#############

# Install the public key for the CRAN repository
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E298A3A825C0D65DFD57CBB651716619E084DAB9

# Add the CRAN repository to the sources list
RUN echo "deb https://cloud.r-project.org/bin/linux/ubuntu jammy-cran40/" >> /etc/apt/sources.list

# Set the DEBIAN_FRONTEND environment variable to noninteractive
ENV DEBIAN_FRONTEND noninteractive

# Update the package lists again and install R
RUN apt-get update && apt-get install -y r-base

# Install needed R packages
RUN Rscript -e "install.packages(c('ggplot2', 'pheatmap', 'ggrepel'))"

############
# Add user #
############

# Add user "dockeruser"
ARG UID=1000
ARG GID=1000

RUN groupadd -g "${GID}" dockeruser \
  && useradd --create-home --no-log-init -u "${UID}" -g "${GID}" dockeruser

# To change default user from root -> dockeruser
#USER dockeruser

# Get back to entry dir
WORKDIR /usr/share/convert-pheno
