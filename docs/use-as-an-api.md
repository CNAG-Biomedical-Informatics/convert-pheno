# As an API

In some cases, it's simply more elegant to send and receive the data from an API. This way, you don't have to worry about installing dependencies, etc.

We have created a very light API that will allow you to send `POST` requests and receive `JSON`. Just make sure to send your data in the proper format.

```JSON
{
 "data": {...}
 "method": "pxf2bff"
}
```

Please see more detailed instructions at this [README](https://github.com/mrueda/convert-pheno/tree/main/api).

!!! Warning "About API location"
    The API should be installed **locally** in your server. This way you don't have to worry about security, etc.
    Now, depending on user's adoption, in the future we may launch a [CNAG](https://www.cnag.crg.eu)-based API service.
