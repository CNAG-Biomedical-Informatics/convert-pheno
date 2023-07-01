#!/usr/bin/env bash
set -euo pipefail

wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/python/main.py

if [ ! -d "local" ]; then
  mkdir local
fi

cpanm --notest --local-lib=local/ Carton
echo "requires 'Convert::Pheno';" > cpanfile
carton install
pip3 install "fastapi[all]"
git clone https://github.com/tkluck/pyperler
cd pyperler && make install 2> install.log
cd ..

