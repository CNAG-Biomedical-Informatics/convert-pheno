`Convert-Pheno` is a toolkit consisting of several components. The core is a [Perl module](https://metacpan.org/pod/Convert%3A%3APheno) which serves as a node for the [command-line interface](use-as-commad-line-interface.md) and the [API](use-as-an-api.md). The Perl module can be used in Python with an included Python Binding that works out of the box with the [containerized version](https://github.com/cnag-biomedical-informatics/convert-pheno#containerized). The [Web App](https://cnag-biomedical-informatics.github.io/convert-pheno-ui) is built on top of the [command-line interface](use-as-commad-line-interface.md).

<figure markdown>
  ```mermaid
  %%{init: {'theme':'neutral'}}%%
  graph TB
    subgraph "Perl"
    A[Module]--> B[CLI]
    A[Module]--> C[API]
    end

    subgraph "Python / JavaScript"
    B --> D[Web App UI]
    end

    subgraph "Python"
    A --> |Python Binding| E[Module]
    E --> F[API]
    end


    style A fill: #6495ED, stroke: #6495ED
    style B fill: #6495ED, stroke: #6495ED
    style C fill: #6495ED, stroke: #6495ED
    style D fill: #AFEEEE, stroke: #AFEEEE
    style E fill: #FFFF33, stroke: #FFFF33
    style F fill: #FFFF33, stroke: #FFFF33
  ```
  <figcaption>Diagram showing Convert-Pheno implementation</figcaption>
</figure>
