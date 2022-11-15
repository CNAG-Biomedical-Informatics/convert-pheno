#!/usr/bin/env make

SHELL := /bin/bash

install:
	sudo apt-get install cpanminus
	cpanm --sudo --installdeps .	

install-carton:
	sudo apt-get install cpanminus
	cpanm --sudo Carton
	carton install

test:
	prove -l

test-carton:
	carton exec -- prove -l
