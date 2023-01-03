# As an API

In some cases, it's simply more elegant to send and receive the data from an API (as a [microservice](https://en.wikipedia.org/wiki/Microservices)). 
For this reason, we have created a very light API that will allow you to send `POST` requests and receive `JSON` responses. 

Just make sure to send your `POST` data in the proper format. 

```json
{
 "data": {...}
 "method": "pxf2bff"
}
```

!!! Warning "About API location"
    The API should be installed **locally** at your server. Depending on user's adoption, in the future we may launch a [CNAG](https://www.cnag.crg.eu)-based API service.

We created two versions, one in `Perl` another in `Python`. Both should work out of the box with the [containerized version](https://github.com/mrueda/convert-pheno#containerized).

=== "Perl version"

    Please see more detailed instructions at this [README](https://github.com/mrueda/convert-pheno/tree/main/api/perl#readme-convert-pheno-api-perl-version).

=== "Python version"

    Please see more detailed instructions at this [README](https://github.com/mrueda/convert-pheno/tree/main/api/python#readme-convert-pheno-api-python-version).
