# README Convert-Pheno-API

Here we provide a light API to enable requests/responses to `Convert::Pheno`. 

At the time of writting this (Sep-2022) the API consists of **very basic functionalities**, but this might change (i.e., switch to OpenAPI specification) dependeping on community adoption.

### Notes:

* This API only accepts requests using `POST` http method.
* This API only has one endpoint `/data`.
    
## Installation

    $ cpanm --sudo Mojolicious Convert::Pheno

## How to run

    $ morbo convert-pheno-api # development (default: port 3000)
or 

    $ hypnotoad convert-pheno-api # production (port 8080)


## Examples

### POST with a data file

   $ curl -d "@data.json" -X POST http://localhost:3000/data

`data.json` contents
```
{
  "method": "pxf2bff",
  "data": 
{
  "CONCEPT" : [
    {
      "concept_class_id" : "4-char billing code",
      "concept_code" : "K92.2",
      "concept_id" : 35208414,
      "concept_name" : "Gastrointestinal hemorrhage, unspecified",
      "domain_id" : "Condition",
      "invalid_reason" : undef,
      "standard_concept" : "",
      "valid_end_date" : "2099-12-31",
      "valid_start_date" : "2007-01-01",
      "vocabulary_id" : "ICD10CM"
    }
  ],
  "CONDITION_OCCURRENCE" : [
    {
      "condition_concept_id" : 4112343,
      "condition_end_date" : "2015-10-14",
      "condition_end_datetime" : "2015-10-14 00:00:00",
      "condition_occurrence_id" : 4483,
      "condition_source_concept_id" : 4112343,
      "condition_source_value" : 195662009,
      "condition_start_date" : "2015-10-02",
      "condition_start_datetime" : "2015-10-02 00:00:00",
      "condition_status_concept_id" : 0,
      "condition_status_source_value" : "",
      "condition_type_concept_id" : 32020,
      "person_id" : 263,
      "provider_id" : "\\N",
      "stop_reason" : "",
      "visit_detail_id" : 0,
      "visit_occurrence_id" : 17479
    }
  ],
  "DRUG_ERA" : [
    {
      "drug_concept_id" : 738818,
      "drug_era_end_date" : "1984-10-03",
      "drug_era_id" : 2707,
      "drug_era_start_date" : "1984-09-19",
      "drug_exposure_count" : 1,
      "gap_days" : 5389,
      "person_id" : 181
    }
  ],
  "MEASUREMENT" : [
    {
      "measurement_concept_id" : 3006322,
      "measurement_date" : "1998-10-03",
      "measurement_datetime" : "1998-10-03 00:00:00",
      "measurement_id" : 10204,
      "measurement_source_concept_id" : 3006322,
      "measurement_source_value" : "8331-1",
      "measurement_time" : "1998-10-03",
      "measurement_type_concept_id" : 5001,
      "operator_concept_id" : 0,
      "person_id" : 974,
      "provider_id" : 0,
      "range_high" : "\\N",
      "range_low" : "\\N",
      "unit_concept_id" : 0,
      "unit_source_value" : undef,
      "value_as_concept_id" : 0,
      "value_as_number" : "\\N",
      "value_source_value" : undef,
      "visit_detail_id" : 0,
      "visit_occurrence_id" : 64994
    }
  ],
  "OBSERVATION" : [
    {
      "observation_concept_id" : 4323208,
      "observation_date" : "1960-06-07",
      "observation_datetime" : "1960-06-07 00:00:00",
      "observation_id" : 25197,
      "observation_source_concept_id" : 4323208,
      "observation_source_value" : 428251008,
      "observation_type_concept_id" : 38000276,
      "person_id" : 1504,
      "provider_id" : 0,
      "qualifier_concept_id" : 0,
      "qualifier_source_value" : undef,
      "unit_concept_id" : 0,
      "unit_source_value" : undef,
      "value_as_concept_id" : 0,
      "value_as_number" : "\\N",
      "value_as_string" : "",
      "visit_detail_id" : 0,
   }
      "visit_occurrence_id" : 100221
  ],
  "OBSERVATION_PERIOD" : [
    {
      "observation_period_end_date" : "2007-02-06",
      "observation_period_id" : 6,
      "observation_period_start_date" : "1963-12-31",
      "period_type_concept_id" : 44814724,
      "person_id" : 6
    }
  ],
  "PERSON" : [
    {
      "birth_datetime" : "1963-12-31 00:00:00",
      "care_site_id" : "\\N",
      "day_of_birth" : 31,
      "ethnicity_concept_id" : 0,
      "ethnicity_source_concept_id" : 0,
      "ethnicity_source_value" : "west_indian",
      "gender_concept_id" : 8532,
      "gender_source_concept_id" : 0,
      "gender_source_value" : "F",
      "location_id" : "\\N",
      "month_of_birth" : 12,
      "person_id" : 6,
      "person_source_value" : "001f4a87-70d0-435c-a4b9-1425f6928d33",
      "provider_id" : "\\N",
      "race_concept_id" : 8516,
      "race_source_concept_id" : 0,
      "race_source_value" : "black",
      "year_of_birth" : 1963
    }
]
}
}
```
