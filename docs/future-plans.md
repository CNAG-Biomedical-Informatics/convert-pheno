```mermaid
  gantt
    title Convert-Pheno Roadmap*
    dateFormat  YYYY-MM-DD

    section Relases
    Alpha                     :done,      r1, 2023-01-01, 90d
    Beta                      :active,    r2, after m1, 500d
    v1                        :           r3, after r2, 310d

    section Publication
    Write manuscript          :done,      m1, 2023-01-01, 90d
    Submission                :active,    m2, after m1, 240d
    Paper acceptance          :milestone, after m2, 0d

    section Formats
    OMOP-CDM (out)  :crit, f1, 2024-01-01, 230d
    OpenEHR         :      f2, after f1, 150d
    HL7/FHIR        :      f3, after f2, 150d

    section Extensions
    User interface            :done,   e1, 2023-01-01, 90d
    User interface (Extended) :        after m2, 545d
```

`*The roadmap is subject to revisions and may evolve over time`

##### last change 2023-11-14 by Manuel Rueda [:fontawesome-brands-github:](https://github.com/mrueda)
