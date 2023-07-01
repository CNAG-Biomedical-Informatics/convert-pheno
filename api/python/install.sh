#!/usr/bin/env bash
set -euo pipefail

wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/python/main.py
mkdir local
cpanm --local-lib=local/ Carton
echo "requires 'Convert::Pheno';" > cpanfile
carton install
pip3 install "fastapi[all]"
git clone https://github.com/tkluck/pyperler
cd pyperler && make install 2> install.log
cd ..

