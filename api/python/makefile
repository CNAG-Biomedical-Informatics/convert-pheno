#!/usr/bin/env make

SHELL := /bin/bash

install-carton:
	cpanm --local-lib=$(HOME)/perl5 Carton # install Perl dependency manager Carton at ~/perl5
	wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/python/main.py
	echo "requires 'Convert::Pheno';" >> cpanfile
	export PATH=$$PATH:$(HOME)/perl5/bin; export PERL5LIB=$(HOME)/perl5/lib/perl5:$$PERL5LIB; carton install # install dependencies at local/
	pip3 install "fastapi[all]"
	git clone https://github.com/tkluck/pyperler
	cd pyperler; make install 2> install.log
