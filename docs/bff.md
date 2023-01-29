**BFF** stands for **B**eacon **F**riendly **F**ormat. The [BFF](https://b2ri-documentation.readthedocs.io/en/latest/data-ingestion) consists of 7 `JSON` files that match the 7 entities of the [Beacon v2 Models](https://docs.genomebeacons.org/models).

<figure markdown>
   ![Beacon v2](img/beacon-v2-models.png){ width="300" }
   <figcaption> Entities in Beacon v2 Models</figcaption>
</figure>

!!! Abstract "About Beacon v2 Models' entities"
    Out of these 7 entities, [individuals](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema) is typically the only one that contain phenotypic data. Other entities such as [cohorts](https://docs.genomebeacons.org/schemas-md/cohortsindividuals_defaultSchema) or [datasets](https://docs.genomebeacons.org/schemas-md/datasets_defaultSchema) may also contain useful information, but their conversion is generally not challenging as they mostly contain text.

   `Convert-Pheno` accepts as input data from the [individuals](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema) entity in [BFF](https://b2ri-documentation.readthedocs.io/en/latest/data-ingestion) format (`individuals.json`).

!!! Tip "Browsing BFF vs `JSON` data"
    You can browse a public BFF v2 file with [Datasette](https://lite.datasette.io/?json=https%3A%2F%2Fraw.githubusercontent.com%2Fmrueda%2Fconvert-pheno%2Fmain%2Ft%2Fomop2bff%2Fout%2Findividuals.json#/data?sql=select+*+from+individuals).

## BFF (individuals) as input ![BFF](https://avatars.githubusercontent.com/u/33450937?s=200&v=4){ width="20" }

=== "Command-line"

    When using the `convert-pheno` command-line interface, simply ensure the [correct syntax](https://github.com/mrueda/convert-pheno#synopsis) is provided.

    !!! Tip "About `JSON` data in `individuals.json`"
        Note that the input `-ibff` file can consist of one individual (one JSON object) or a list of individuals (a JSON array of objects). The output `-opxf` file will replicate the data organization of the input file.

    ```
    convert-pheno -ibff individuals.json -opxf phenopacket.json
    ```

=== "Module"

    The concept is to pass the necessary information as a hash (in Perl) or dictionary (in Python).

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
       "id" : "phenopacket_id.AUNb6vNX1",
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
