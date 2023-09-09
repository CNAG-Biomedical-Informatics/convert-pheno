# HIGH PRIORITY

* Add input data in Pheno.pm

# $os in mac with perl ? Darwin or darwin?

* Mermaid PXF to BFF


# LOW PRIORITY

* range_high and range_low OMOP value?


# OPTIONAL

* Dataset-JSON    :      f3, after f2, 120d

* Can we use use JSON::Path or Mojo::JSON::Pointer to simplify stuff somewhere?

* Optimize code (takes some time to coerce values (at read and the other serializing)
  Can it be optimized? I tried on Feb-2023 and I could not....

* Use DBHUB.io to display data on Databases??

* Create template for Python Module?

* Other CDISC formats - Dataset JSON, ODM v2, etc.

* Add Carp and confess...is it really needed? Too verbose

* README for module in CPAN (classes/methods)

** add changes to tag in Github
   like this
   https://github.com/ingydotnet/yaml-libyaml-pm/tags
   it needs bash to fetch the actual data and I only include tags for releases

# Notes

* diseases or phenotypicFeatures ?? (see below)

In Phenopackets a disease is when it's diagnosed (OMIM for rare diseases)
  Comorbidities are not "directly" diagnosed..
PhenotypicFeatures can also be diseases 
  - terms which are present / absent (HPO terms)
