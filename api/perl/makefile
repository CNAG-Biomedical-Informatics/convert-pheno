#!/usr/bin/env make

SHELL := /bin/bash

install:
	sudo apt-get install cpanminus libbz2-dev zlib1g-dev libperl-dev libssl-dev
	wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/cpanfile
	wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/convert-pheno-api
	wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/openapi.json
	echo "requires 'Convert::Pheno';" >> cpanfile
	cpanm --notest --sudo --installdeps .

install-carton:
	sudo apt-get install cpanminus libbz2-dev zlib1g-dev libperl-dev libssl-dev # sys-level
	cpanm --local-lib=~/perl5 local::lib && eval $$(perl -I ~/perl5/lib/perl5/ -Mlocal::lib) # set-up ~/perl5
	cpanm --local-lib=~/perl5 Carton # install Perl dependency manager Carton at ~/perl5
	export PATH=$$PATH:~/perl5/bin
	wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/cpanfile
	wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/convert-pheno-api
	wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/openapi.json
	echo "requires 'Convert::Pheno';" >> cpanfile
	carton install # install dependencies at local/
