---
title: Future Plans
sidebar_label: Future Plans
---

# Future Plans

Convert-Pheno already supports a broad set of clinical and phenotypic data
formats. The next steps are mainly about learning from more real datasets and
improving the parts that users find most useful. These are priorities rather
than promises for a particular release.

<div className="roadmap-grid">
  <article className="roadmap-card roadmap-card--active">
    <span className="roadmap-kicker">CDISC ODM</span>
    <h2>Work with more EDC exports</h2>
    <p>Test files produced by REDCap, OpenClinica, and other ODM-based systems so differences between real exports are handled clearly.</p>
  </article>
  <article className="roadmap-card roadmap-card--active">
    <span className="roadmap-kicker">Recent inputs</span>
    <h2>Learn from more datasets</h2>
    <p>Use cBioPortal, FHIR and mCODE, Dataset-JSON, Dataset-XML, and openEHR data from independent projects and refine the mappings from their feedback.</p>
  </article>
  <article className="roadmap-card">
    <span className="roadmap-kicker">Mappings</span>
    <h2>Fill useful gaps</h2>
    <p>Add fields and records when source datasets contain meaningful information that has a clear place in the target format.</p>
  </article>
  <article className="roadmap-card">
    <span className="roadmap-kicker">Large studies</span>
    <h2>Reduce memory use</h2>
    <p>Improve how large FHIR and CDISC datasets are processed when representative files show where the current in-memory approach becomes limiting.</p>
  </article>
  <article className="roadmap-card">
    <span className="roadmap-kicker">Beacon v2</span>
    <h2>Support more BFF records</h2>
    <p>Add entities such as analyses and runs when an input format provides enough information to create useful, valid records.</p>
  </article>
  <article className="roadmap-card">
    <span className="roadmap-kicker">Additional formats</span>
    <h2>Follow real use cases</h2>
    <p>Consider formats such as SAS XPORT, C-CDA, and PCORnet when there is a concrete user need and representative data for testing.</p>
  </article>
  <article className="roadmap-card">
    <span className="roadmap-kicker">Validation</span>
    <h2>Keep examples and checks current</h2>
    <p>Add representative datasets and continue checking generated files with the validators available for each target format.</p>
  </article>
</div>
