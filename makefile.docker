#!/usr/bin/env make

SHELL := /bin/bash

install:
	docker build -t cnag/convert-pheno:latest .

run:
	docker run -tid --name convert-pheno cnag/convert-pheno:latest

enter:
	docker exec -ti convert-pheno bash

test:
	docker exec -ti convert-pheno prove -l

stop:	
	docker stop convert-pheno

clean: 
	docker rm -f convert-pheno
	docker rmi cnag/convert-pheno:latest
