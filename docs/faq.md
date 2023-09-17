Frequently Asked Questions

## General

??? faq "What does `Convert-Pheno` do?"

    This tool facilitates the conversion of clinical data between commonly used formats, such as [GA4GH standards](https://www.ga4gh.org), to enable **secure data sharing** and discovery through **semantic interoperability**.

    ##### last change 2023-01-05 by Manuel Rueda [:fontawesome-brands-github:](https://github.com/mrueda)

??? faq "Is `Convert-Pheno` free?"

    Yes. See the [license](https://github.com/mrueda/convert-pheno/blob/main/LICENSE).

    ##### last change 2023-01-04 by Manuel Rueda [:fontawesome-brands-github:](https://github.com/mrueda)

??? faq "Can I use `Convert-Pheno` in _production_ software?"

    It's still in Beta so expect some bumps ahead.

    ##### last change 2023-06-27 by Manuel Rueda [:fontawesome-brands-github:](https://github.com/mrueda)

??? faq "If I use `Convert-Pheno` to convert my data to [Beacon v2 Models](bff.md), does this mean I have a Beacon v2?"

    I am afraid not. Beacon v2 is an [API specification](https://docs.genomebeacons.org), and the [Beacon v2 Models](bff.md) are merely a component of it. In order to _light a Beacon v2_, it is necessary to load the `JSON` files into a **database** and add an an **API** on top. Currently, it is advisable to utilize the [Beacon v2 Reference Implementation](https://b2ri-documentation.readthedocs.io/en/latest) which includes the database, the Beacon v2 API, and other necessary components.

    See below an example in how to integrate an OMOP-CDM export from SQL with Beacon v2.

    <figure markdown>
      ![B2RI](img/convert-pheno-beacon-integration.png){ width="600" }
      <figcaption>Beacon v2 RI integration</figcaption>
    </figure>

    ##### last change 2023-06-20 by Manuel Rueda [:fontawesome-brands-github:](https://github.com/mrueda)

??? faq "What is the difference between Beacon v2 Models and Beacon v2?"

    **Beacon v2** is a specification to build an [API](https://docs.genomebeacons.org). The [Beacon v2 Models](https://docs.genomebeacons.org/models/) define the format for the API's responses to queries regarding biological data. With the help of `Convert-Pheno`, text files ([BFF](bff.md)) that align with this response format can be generated. By doing so, the BFF files can be integrated into a non-SQL database, such as MongoDB, without the API having to perform any additional data transformations internally.

    ##### last change 2023-02-13 by Manuel Rueda [:fontawesome-brands-github:](https://github.com/mrueda)

??? faq "Are you planning in supporting other clinical data formats?"

    Afirmative. Please check our [roadmap](future-plans.md) for more information.

    ##### last change 2023-01-04 by Manuel Rueda [:fontawesome-brands-github:](https://github.com/mrueda)

??? faq "Are longitudinal data supported?"

    Although Beacon v2 and Phenopackets v2 allow for storing time information in some properties, there is currently no way to associate medical visits to properties. To address this:

    * `omop2bff` -  we added an _ad hoc_ property (**_visit**) to store medical visit information for longitudinal events in variables that have it (e.g., measures, observations, etc.).

    * `redcap2bff` - In REDCap, visit/event information is not stored at the record level. We added this information inside `info` property.

    We raised this issue to the respective communities in the hope of a more permanent solution.

    ##### last change 2023-03-24 by Manuel Rueda [:fontawesome-brands-github:](https://github.com/mrueda)


??? faq "I have a set of PXF files encoded with HPO and ICD-10 ontologies and I want to convert them to BFF but encoded with OMIM and SNOMED-CT ontologies. Can you help me?"

    Neither Phenopackets v2 nor Beacon v2 prescribe the use of a specific ontology; they simply provide **recommendations** on their websites. Thereby, `Convert-Pheno` does not change the source ontologies.

    Now, IMHO, it's generally easier to inter-convert ontologies than to inter-convert raw data to ontologies. So there is that advantage... :smile:.

    !!! Abstract "Nota Bene:"
        A  standard that does enforce the use of an **standardized vocabulary** is [OMOP-CDM](omop-cdm.md), you may wanna check it out.

    ##### last change 2023-09-16 by Manuel Rueda [:fontawesome-brands-github:](https://github.com/mrueda)


## Installation

??? faq "I am installing `Convert-Pheno` from source ([non-containerized version](https://github.com/cnag-biomedical-informatics/convert-pheno#non-containerized)) but I can't make it work. Any suggestions?"

    #### Problems with Python / PyPerler

    !!! Failure "About PyPerler installation"
        Apart from [PypPerler](https://github.com/tkluck/pyperler#quick-install) itself, you may need to install `cython3` and `libperl-dev` to make it work.

        `sudo apt-get install cython3 libperl-dev`


    ##### last change 2023-01-04 by Manuel Rueda [:fontawesome-brands-github:](https://github.com/mrueda)
