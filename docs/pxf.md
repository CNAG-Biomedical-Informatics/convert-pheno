**PXF** stands for **P**henotype e**X**change **F**ormat. Phenopackets v2 [documentation](https://phenopacket-schema.readthedocs.io/en/latest/basics.html).

<figure markdown>
   ![Phenopackets v2](https://www.ga4gh.org/wp-content/uploads/2022/02/phenopachets-v2-final-1.jpeg){ width="500" }
   <figcaption>Figure extracted from www.ga4gh.org</figcaption>
</figure>

Phenopackets organize information using [top-level elements](https://phenopacket-schema.readthedocs.io/en/latest/toplevel.html). Our software, `Convert-Pheno`, specifically processes data from the [Phenopacket element](https://phenopacket-schema.readthedocs.io/en/latest/phenopacket.html), serialized in [PXF](http://phenopackets.org/) format.

??? Tip "Browsing PXF `JSON` data"

    You can browse a public Phenopackets v2 file with onf of teh following **JSON viewers**:

    * [JSON Crack](https://jsoncrack.com/editor?json=https://raw.githubusercontent.com/cnag-biomedical-informatics/convert-pheno/main/t/pxf2bff/in/pxf.json)
    * [JSON Hero](https://jsonhero.io/new?url=https://raw.githubusercontent.com/cnag-biomedical-informatics/convert-pheno/main/t/pxf2bff/in/pxf.json)
    * [Datasette](https://lite.datasette.io/?json=https%3A%2F%2Fraw.githubusercontent.com%2Fcnag-biomedical-informatics%2Fconvert-pheno%2Fmain%2Ft%2Fomop2pxf%2Fout%2Fpxf.json#/data?sql=select+*+from+pxf)

## PXF (Phenopacket top-element) as input ![PXF](https://avatars.githubusercontent.com/u/17553567?s=280&v=4){ width="20" }

=== "Command-line"

    When using the `convert-pheno` command-line interface, simply ensure the [correct syntax](https://github.com/cnag-biomedical-informatics/convert-pheno#synopsis) is provided.

    ```
    convert-pheno -ipxf ipxf.json -obff individuals.json
    ```

    ??? Tip "About `JSON` data structure in I/O files"
        Note that the input `-ipxf` file can consist of one individual (one JSON object) or a list of individuals (a JSON array of objects). The output `--obff` file will replicate the data structure of the input file.


    ??? Warning "About `biosamples` and `interpretations`"
        If these properties are present, they will be included in `individuals.json` within the `info.phenopacket` field as unprocessed data, as they are not mapped to any specific entity within the Beacon v2 Models. See additional info [here](mapping-steps.md).

=== "Module"

    The concept is to pass the necessary information as a hash (in Perl) or dictionary (in Python).

    === "Perl"

        ```Perl
        $bff = {
            data => $my_pxf_json_data,
            method => 'pxf2bff'
        };
        ```
   
    === "Python"
        ```Python
        bff = {
             "data" : my_pxf_json_data,
             "method" : "pxf2bff"
        }
        ```

=== "API"

    The data will be sent as `POST` to the API's URL (see more info [here](use-as-an-api.md)).
    ```
    {
    "data": {...}
    "method": "pxf2bff"
    }
    ```

Please find below examples of data:

=== "PXF (input)"
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

=== "BFF (output)"
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
