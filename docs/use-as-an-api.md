In some cases, using an API for sending and receiving data as a microservice may be more efficient. To address this, we have developed a lightweight REST API that allows for sending `POST` requests and receiving `JSON` responses

## Usage

Just make sure to send your `POST` data in the proper format. 

`curl -d "@data.json" -H 'Content-Type: application/json' -X POST http://localhost:3000/api`

where `data.json` looks like the below:

```json
{
 "data": {...}
 "method": "pxf2bff"
}
```

!!! Note "Interactive API specification"
    Please find [here](redoc-static.html) interactive documentation (built with [ReDoc](https://redocly.github.io/redoc/)).

## Included APIs

We included two flavours of the same API, one in `Perl` and another in `Python`.Both APIs were created by using OpenAPI 3.0.2 schema and should work out of the box with the [containerized version](https://github.com/cnag-biomedical-informatics/convert-pheno#containerized).

=== "Perl version"

    Please see more detailed instructions at this [README](https://github.com/cnag-biomedical-informatics/convert-pheno/tree/main/share/api/perl#readme-convert-pheno-api-perl-version).

=== "Python version"

    Please see more detailed instructions at this [README](https://github.com/cnag-biomedical-informatics/convert-pheno/tree/main/share/api/python#readme-convert-pheno-api-python-version).

!!! Question "Local or remote installation?"
    The API should be installed on a **local** server.
