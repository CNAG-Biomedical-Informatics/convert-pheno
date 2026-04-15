#!/usr/bin/env bash
set -euo pipefail

mkdir -p api/python api/perl lib local

wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/python/main.py -O api/python/main.py
wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/lib/convertpheno.py -O lib/convertpheno.py
wget https://raw.githubusercontent.com/CNAG-Biomedical-Informatics/convert-pheno/main/api/perl/json_bridge.pl -O api/perl/json_bridge.pl

cpanm --notest --local-lib=local/ Carton
echo "requires 'Convert::Pheno';" > cpanfile
carton install
pip3 install "fastapi[all]"
