#!/usr/bin/env python3
#
#   Example script on how to use Convert::Pheno directly from Python
#
#   This file is part of Convert::Pheno
#
#   Last Modified: Apr/15/2026
#
#   $VERSION taken from Convert::Pheno
#
#   Copyright (C) 2022-2026 Manuel Rueda - CNAG (manuel.rueda@cnag.eu)
#
#   License: Artistic License 2.0

import json
import sys

# Provide the path to <convert-pheno/lib> when running from the repository
# checkout instead of an installed Python environment.
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

    # Create request payload. Module parameters are passed in one flat payload,
    # unlike the structured HTTP API. PythonBinding shells out to the Perl JSON
    # bridge under api/perl/json_bridge.pl, but it can still be used directly
    # from Python code without running the HTTP API.
    payload = {
        "method": "pxf2bff",
        "data": my_pxf_json_data,
        "test": 1,
    }

    # Create bridge-backed binding object
    convert = PythonBinding(payload)

    # Run method convert_pheno and print formatted JSON
    print(json.dumps(convert.convert_pheno(), indent=4, sort_keys=True))


if __name__ == "__main__":
    main()
