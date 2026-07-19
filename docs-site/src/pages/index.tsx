import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import useBaseUrl from '@docusaurus/useBaseUrl';
import styles from './index.module.css';

export default function Home() {
  const diagramUrl = useBaseUrl('/img/convert-pheno-flow.svg');
  const objectiveUrl = useBaseUrl('/img/convert-pheno-objective.svg');

  return (
    <Layout
      title="Convert-Pheno"
      description="Open-source software for interconverting clinical and phenotypic data models">
      <main className={styles.page}>
        <section className={styles.hero}>
          <div className={styles.heroInner}>
            <div className={styles.heroCopy}>
              <p className={styles.kicker}>Clinical data model conversion</p>
              <h1>Convert-Pheno</h1>
              <p className={styles.claim}>
                Conversion of clinical and phenotypic data between supported data models.
              </p>
              <p className={styles.lede}>
                Open-source software for reproducible transformations among Beacon v2
                Models, Phenopackets v2, OMOP-CDM, and mapping-based clinical data
                sources. The command-line interface is the primary user interface;
                Perl, Python, and HTTP(s) interfaces are also available for integration.
              </p>
              <div className={styles.actions}>
                <Link className={styles.action} to="/conversion-recipes">
                  Quickstart
                </Link>
                <Link className={styles.action} to="/supported-formats">
                  Supported Formats
                </Link>
                <Link className={styles.action} to="/citation">
                  Publications
                </Link>
              </div>
            </div>
            <img
              className={styles.objective}
              src={objectiveUrl}
              alt="Supported input data models are converted by Convert-Pheno into a selected output data model"
            />
          </div>
        </section>

        <section className={styles.workflow}>
          <div className={styles.sectionHeading}>
            <div>
              <p className={styles.sectionLabel}>Conversion architecture</p>
              <h2>A common target model connects supported routes.</h2>
            </div>
            <p>
              Most conversions normalize source records through Beacon v2 Models
              BFF before writing the output selected by the user.
            </p>
          </div>
          <figure className={styles.diagramFrame}>
            <div className={styles.diagramScroller}>
              <img
                src={diagramUrl}
                alt="Supported inputs pass through Convert-Pheno and the Beacon v2 Models BFF target model to supported outputs"
              />
            </div>
            <figcaption>
              BFF is the internal target model for most conversion routes; final
              output is not limited to BFF.
            </figcaption>
          </figure>
        </section>

        <section className={styles.scopeSection}>
          <div className={styles.sectionHeading}>
            <div>
              <p className={styles.sectionLabel}>Current scope</p>
              <h2>Supported operations</h2>
            </div>
            <p>
              Conversion behavior depends on the selected source and output route.
              Route-specific requirements are documented with the corresponding format.
            </p>
          </div>
          <div className={styles.operationGrid}>
            <article className={styles.operation}>
              <span>Structured models</span>
              <h3>Convert BFF, PXF, and OMOP-CDM</h3>
              <p>Read and write established clinical and phenotypic models through supported routes.</p>
            </article>
            <article className={styles.operation}>
              <span>Mapped sources</span>
              <h3>Transform REDCap, CDISC-ODM, and CSV</h3>
              <p>Use project mapping files to relate source fields to the target model.</p>
            </article>
            <article className={styles.operation}>
              <span>Beacon entities</span>
              <h3>Write entity-aware BFF collections</h3>
              <p>Produce individuals, biosamples, datasets, and cohorts where the route supports them.</p>
            </article>
            <article className={styles.operation}>
              <span>Auditability</span>
              <h3>Retain provenance and inspect searches</h3>
              <p>Preserve source fields and optionally record ontology lookup decisions.</p>
            </article>
          </div>
          <aside className={styles.scopeNote}>
            <strong>Scope</strong>
            <p>
              Convert-Pheno does not replace terminology curation, a general OMOP ETL
              framework, or project-specific review and validation of converted data.
            </p>
          </aside>
        </section>
      </main>
    </Layout>
  );
}
