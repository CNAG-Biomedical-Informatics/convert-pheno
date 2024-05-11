```mermaid
  gantt
    title Convert-Pheno Roadmap*
    dateFormat  YYYY-MM-DD

    section Relases
    Alpha                     :done,      r1, 2023-01-01, 100d
    Beta                      :active,    r2, after m1, 700d
    v1                        :           r3, after r2, 310d

    section Publication
    Write manuscript          :done,      m1, 2023-01-01, 110d
    Submission                :active,    m2, after m1, 240d
    Paper acceptance          :milestone, after m2, 0d

    section Input-Formats
    CSV (in)        :crit, f1, after f0,   80d
    OpenEHR (in)    :      f3, after f2,   150d
    HL7/FHIR (in)   :      f4, after f3,   150d

    section Output-formats
    CSV (out)       :      f0, 2024-02-01, 70d
    OMOP-CDM (out)  :crit, f2, after f1,   230d

    section Extensions
    User interface            :done,   e1, 2023-01-01, 100d
```

`*The roadmap is subject to revisions and may evolve over time`

##### last change 2024-05-10 by Manuel Rueda [:fontawesome-brands-github:](https://github.com/mrueda)
