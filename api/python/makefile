#!/usr/bin/env make

SHELL := /bin/bash

install-carton:
	sudo apt-get install cpanminus libbz2-dev zlib1g-dev libperl-dev libssl-dev # sys-level
	cpanm --local-lib=~/perl5 local::lib && eval $$(perl -I ~/perl5/lib/perl5/ -Mlocal::lib) # set-up ~/perl5
	cpanm --local-lib=~/perl5 Carton # install Perl dependency manager Carton at ~/perl5
	wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/python/main.py
	echo "requires 'Convert::Pheno';" > cpanfile
	carton install # install dependencies at local/
	pip3 install "fastapi[all]"
	git clone https://github.com/tkluck/pyperler
	cd pyperler; make install 2> install.log
	cd ..
