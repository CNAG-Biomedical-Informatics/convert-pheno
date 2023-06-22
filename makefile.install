#!/usr/bin/env make

SHELL := /bin/bash

install:
	sudo apt-get install cpanminus libbz2-dev zlib1g-dev libperl-dev libssl-dev
	cpanm --sudo --installdeps .	

install-carton:
	sudo apt-get install cpanminus libbz2-dev zlib1g-dev libperl-dev libssl-dev
	cpanm --sudo Carton
	carton install

test:
	prove -l

test-carton:
	carton exec -- prove -l
