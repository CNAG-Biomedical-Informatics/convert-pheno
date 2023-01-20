In certain situations, using an API for sending and receiving data (as a microservice) may be more efficient. To accommodate this, we have created a lightweight API that enables sending `POST` requests and receiving `JSON` responses.

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

## Included APIs

We included two flavours of the same API, one in `Perl` and another in `Python`. Both should work out of the box with the [containerized version](https://github.com/mrueda/convert-pheno#containerized).

=== "Perl version"

    Please see more detailed instructions at this [README](https://github.com/mrueda/convert-pheno/tree/main/api/perl#readme-convert-pheno-api-perl-version).

=== "Python version"

    Please see more detailed instructions at this [README](https://github.com/mrueda/convert-pheno/tree/main/api/python#readme-convert-pheno-api-python-version).

!!! Question "Local or remote installation?"
    The API should be installed on a **local** server to enable federated data discovery.
