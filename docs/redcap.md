# REDCap

**REDCap** stands for **R**esearch **E**lectronic **D**ata **Cap**ture.

REDCap [documentation](https://www.project-redcap.org).

## REDCap as input

REDCap projects are by definition “**free format**”, that is, is up to the project creator to establish the identifiers for the variables, data dictionaries, etc. 

!!! Info 
    As stated in the REDCap project creation user’s guide _“We always recommend reviewing your variable names with a statistician or whoever will be analyzing your data. This is especially important if this is the first time you are building a database.”_ 

This freedom of choice makes very difficult (if not impossible) to come up with a solution that is able to handle the plethora of possibilities from REDCap projects.  Still, we have been able to succesfully convert data from REDCap project export to both Beacon v2 and Phenopackets v2. These projects were developed in the context of the [3TR Project](https://3tr-imi.eu).

The idea is to support more REDCap data exports in the future by allowing **one-to-one variable mapping to our template**. 

!!! Important "About REDCap export formats"
    REDCap allows for exporting "All data (all records and fields)" in multiple ways. Here we are accepting the `CSV / Microsoft Excel` format, along with a data dictionary (also in CSV). 
    REDCap `CDISC ODM (XML)` export will be covered in the section about [CDISC-ODM](cdisc.md).

!!! Warning "REDCap API"
    REDCap has a built API, which, in principle could be used to pull data _on-the-fly_ data (instead of data exports). 
    The current version of `Convert::Pheno` does not support REDCap API calls.

### Command-line

If you're using a Beacon v2 JSON file with the `convert-pheno` command-line interface just provide the right [syntax](https://github.com/mrueda/convert-pheno#synopsis):

Note that the we need two (`csv`) files, one for the REDCap export data and another for the dictionaries.

```
convert-pheno -iredcap redcap.csv --redcap-dictionary dictionary.csv -obff individuals.json
```
