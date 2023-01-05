In some cases, it's simply more elegant to send and receive the data from an API (as a [microservice](https://en.wikipedia.org/wiki/Microservices)). 
For this reason, we have created a very light API that will allow you to send `POST` requests and receive `JSON` responses. 

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
    The API should be installed **locally** at your server. The idea is to enable **federated** data discovery. Depending on user's adoption, in the future we may launch a [CNAG](https://www.cnag.crg.eu)-based API service.

