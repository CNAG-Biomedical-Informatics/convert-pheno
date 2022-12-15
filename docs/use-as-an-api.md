# As an API

In some cases, it's simply more elegant to send and receive the data from an API (as a [microservice](https://en.wikipedia.org/wiki/Microservices). 
We have created a very light API that will allow you to send `POST` requests and receive `JSON` responses. Just make sure to send your data in the proper format.

```JSON
{
 "data": {...}
 "method": "pxf2bff"
}
```

## Perl version

Please see more detailed instructions at this [README](https://github.com/mrueda/convert-pheno/tree/main/api/perl).

## Python version

Please see more detailed instructions at this [README](https://github.com/mrueda/convert-pheno/tree/main/api/python).


!!! Warning "About API location"
    The API should be installed **locally** in your server. This way you don't have to worry about security, etc.
    Depending on user's adoption, in the future we may launch a [CNAG](https://www.cnag.crg.eu)-based API service.
