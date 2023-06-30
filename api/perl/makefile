#!/usr/bin/env make

SHELL := /bin/bash

install:
	wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/cpanfile
	wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/convert-pheno-api
	wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/openapi.json
	echo "requires 'Convert::Pheno';" >> cpanfile
	cpanm --notest --sudo --installdeps .

install-carton:
	cpanm --local-lib=$(HOME)/perl5 Carton # install Perl dependency manager Carton at ~/perl5
	wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/cpanfile
	wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/convert-pheno-api
	wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/openapi.json
	echo "requires 'Convert::Pheno';" >> cpanfile
	export PATH=$$PATH:$(HOME)/perl5/bin; export PERL5LIB=$(HOME)/perl5/lib/perl5:$$PERL5LIB; carton install # install dependencies at local/
