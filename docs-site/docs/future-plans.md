---
title: Future Plans
sidebar_label: Future Plans
---

# Future Plans

We expect to improve these areas as Convert-Pheno is used with more datasets.
They are directions rather than promises for a particular release. Routes
described as experimental already work and are tested, but have been used by
fewer independent groups.

<div className="roadmap-grid">
  <article className="roadmap-card roadmap-card--active">
    <span className="roadmap-kicker">CDISC ODM</span>
    <h2>Test more EDC exports</h2>
    <p>Exercise the version-aware ODM 1.3 and 2.0 ClinicalData input with more independently produced REDCap, OpenClinica, and standard ODM snapshots.</p>
  </article>
  <article className="roadmap-card roadmap-card--active">
    <span className="roadmap-kicker">More datasets</span>
    <h2>Test newer input formats</h2>
    <p>Use cBioPortal, FHIR R4 and mCODE, CDISC Dataset-JSON and Dataset-XML, and openEHR data from more independent sources and incorporate feedback from their users.</p>
  </article>
  <article className="roadmap-card">
    <span className="roadmap-kicker">Implemented profiles</span>
    <h2>Broaden mCODE and Dataset-XML evidence</h2>
    <p>Test the mCODE 4.0 stage mapping and Dataset-XML plus Define-XML parser with independently generated datasets before extending their first-class mappings.</p>
  </article>
  <article className="roadmap-card">
    <span className="roadmap-kicker">Mappings</span>
    <h2>Review uncommon cases</h2>
    <p>Work with data owners and domain experts to improve mappings while keeping original source values easy to trace.</p>
  </article>
  <article className="roadmap-card">
    <span className="roadmap-kicker">Large files</span>
    <h2>Use less memory</h2>
    <p>Explore ways to process larger FHIR, Dataset-JSON, and Dataset-XML inputs without keeping every record in memory at once.</p>
  </article>
  <article className="roadmap-card">
    <span className="roadmap-kicker">Beacon v2</span>
    <h2>Add more BFF entities</h2>
    <p>Add analyses and runs when a source format contains enough information to create useful records.</p>
  </article>
  <article className="roadmap-card">
    <span className="roadmap-kicker">Validation</span>
    <h2>Keep checks current</h2>
    <p>Add test datasets and continue checking generated files with the relevant format validators.</p>
  </article>
</div>
