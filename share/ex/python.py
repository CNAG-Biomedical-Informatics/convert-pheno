#!/usr/bin/env python3
#
#   Example script on how to use Convert::Pheno in Python
#
#   This file is part of Convert::Pheno
#
#   Last Modified: Dec/14/2022
#
#   $VERSION taken from Convert::Pheno
#
#   Copyright (C) 2022-2023 Manuel Rueda - CNAG (manuel.rueda@cnag.crg.eu)
#
#   License: Artistic License 2.0

import json
import sys
sys.path.append('../../lib/')
from convertpheno import PythonBinding


def main():

    # Example PXF data
    my_pxf_json_data = {
      "phenopacket": {
        "id": "P0007500",
        "subject": {
          "id": "P0007500",
          "dateOfBirth": "unknown-01-01T00:00:00Z",
          "sex": "FEMALE"
        }
      }
    }

    # Create dictionary
    json_data = {
        "method": "pxf2bff",
        "data": my_pxf_json_data
    }

    # Creating object for class PythonBinding
    convert = PythonBinding(json_data)

    # Run method convert_pheno and beautify with json.dumps
    print(json.dumps(convert.convert_pheno(), indent=4, sort_keys=True))


if __name__ == "__main__":
    main()
