**BFF** stands for **B**eacon **F**riendly **F**ormat. The BFF consists of 7 `JSON` files that match the 7 entities of the [Beacon v2 default models](https://docs.genomebeacons.org/models).

From these 7 files, often `individuals.json` is the only file containing [phenotypic data](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema).

Other entities such as [cohorts](https://docs.genomebeacons.org/schemas-md/cohortsindividuals_defaultSchema) or [datasets](https://docs.genomebeacons.org/schemas-md/datasets_defaultSchema) may contain valuable info, but being mostly text, its conversion does not represent a challenge.

## BFF (individuals) as input

=== "Command-line"

    If you're using a Beacon v2 JSON file with the `convert-pheno` command-line interface just provide the right [syntax](https://github.com/mrueda/convert-pheno#synopsis):

    !!! Note "About data types"
        Note that the file can consist of a single individual (JSON object) or multiple ones (JSON array of objects).

    ```
    convert-pheno -ibff individuals.json -opxf phenopacket.json
    ```

=== "Module"

    The idea is that we will pass the essential information as a hash (Perl) or dictionary (Python).

    `Perl`
    ```Perl
    $bff = {
        data => $my_bff_json_data,
        method => 'bff2pxf'
    };
    ```

    `Python`
    ```Python
    bff = {
         "data" : my_bff_json_data,
         "method" : "bff2pxf"
    }
    ```

=== "API"

    The data will be sent as `POST` to the API's URL (see more info [here](use-as-an-api.md)).
    ```
    {
    "data": {...}
    "method": "bff2pxf"
    }
    ```

Please find below examples of data:

=== "BFF (input)"
    ```json
    {
      "ethnicity": {
        "id": "NCIT:C42331",
        "label": "African"
      },
      "id": "HG00096",
      "info": {
        "eid": "fake1"
      },
      "interventionsOrProcedures": [
        {
          "procedureCode": {
            "id": "OPCS4:L46.3",
            "label": "OPCS(v4-0.0):Ligation of visceral branch of abdominal aorta NEC"
          }
        }
      ],
      "measures": [
        {
          "assayCode": {
            "id": "LOINC:35925-4",
            "label": "BMI"
          },
          "date": "2021-09-24",
          "measurementValue": {
            "quantity": {
              "unit": {
                "id": "NCIT:C49671",
                "label": "Kilogram per Square Meter"
              },
              "value": 26.63838307
            }
          }
        },
        {
          "assayCode": {
            "id": "LOINC:3141-9",
            "label": "Weight"
          },
          "date": "2021-09-24",
          "measurementValue": {
            "quantity": {
              "unit": {
                "id": "NCIT:C28252",
                "label": "Kilogram"
              },
              "value": 85.6358
            }
          }
        },
        {
          "assayCode": {
            "id": "LOINC:8308-9",
            "label": "Height-standing"
          },
          "date": "2021-09-24",
          "measurementValue": {
            "quantity": {
              "unit": {
                "id": "NCIT:C49668",
                "label": "Centimeter"
              },
              "value": 179.2973
            }
          }
        }
      ],
      "sex": {
        "id": "NCIT:C20197",
        "label": "male"
      }
    }
    ```
    
=== "PXF (output)"
    ```json
    {
       "diseases" : [],
       "id" : null,
       "measurements" : [
          {
             "assay" : {
                "id" : "LOINC:35925-4",
                "label" : "BMI"
             },
             "value" : {
                "quantity" : {
                   "unit" : {
                      "id" : "NCIT:C49671",
                      "label" : "Kilogram per Square Meter"
                   },
                   "value" : 26.63838307
                }
             }
          },
          {
             "assay" : {
                "id" : "LOINC:3141-9",
                "label" : "Weight"
             },
             "value" : {
                "quantity" : {
                   "unit" : {
                      "id" : "NCIT:C28252",
                      "label" : "Kilogram"
                   },
                   "value" : 85.6358
                }
             }
          },
          {
             "assay" : {
                "id" : "LOINC:8308-9",
                "label" : "Height-standing"
             },
             "value" : {
                "quantity" : {
                   "unit" : {
                      "id" : "NCIT:C49668",
                      "label" : "Centimeter"
                   },
                   "value" : 179.2973
                }
             }
          }
       ],
       "medicalActions" : [
          {
             "procedure" : {
                "code" : {
                   "id" : "OPCS4:L46.3",
                   "label" : "OPCS(v4-0.0):Ligation of visceral branch of abdominal aorta NEC"
                },
                "performed" : {
                   "timestamp" : "1900-01-01T00:00:00Z"
                }
             }
          }
       ],
       "metaData" : null,
       "subject" : {
          "id" : "HG00096",
          "sex" : "MALE",
          "vitalStatus" : {
             "status" : "ALIVE"
          }
       }
    }
    ```
