```mermaid
  gantt
    title Convert-Pheno Roadmap
    dateFormat  YYYY-MM-DD

    section Relases
    Alpha                     :done,      r1, 2023-01-01, 90d
    Beta                      :active,    r2, after r1, 185d
    v1                        :           r3, after r2, 365d

    section Publication
    Write manuscript          :done,      m1, 2023-01-01, 90d
    Submission                :active,    m2, after m1, 90d
    Paper acceptance          :milestone, after m2, 0d

    section Formats
    OMOP-CDM (out)  :crit, f1, 2023-07-01, 120d
    OpenEHR         :      f2, after f1, 120d
    Dataset-JSON    :      f3, after f2, 120d
    HL7/FHIR        :      f4, after f3, 120d

    section Extensions
    User interface            :done,   e1, 2023-01-01, 90d
    User interface (Extended) :        after m2, 360d
```

##### last change 2023-04-10 by Manuel Rueda [:fontawesome-brands-github:](https://github.com/mrueda)
