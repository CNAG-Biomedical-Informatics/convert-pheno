import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import useBaseUrl from '@docusaurus/useBaseUrl';
import styles from './index.module.css';

export default function Home() {
  const logoUrl = useBaseUrl('/img/CP-logo.png');

  return (
    <Layout
      title="Convert-Pheno"
      description="A toolkit for interconverting clinical and phenotypic data models">
      <main className={styles.page}>
        <section className={styles.hero}>
          <div className={styles.heroGrid}>
            <div className={styles.copy}>
              <p className={styles.kicker}>Convert-Pheno</p>
              <h1>Clinical and phenotypic data conversion across standard data models.</h1>
              <p className={styles.lede}>
                Convert between Beacon v2 Models, Phenopackets v2, OMOP-CDM,
                REDCap, CDISC-ODM, CSV, and related exchange formats through a
                command-line tool, Perl module, Python binding, and HTTP(s) APIs.
              </p>
              <div className={styles.actions}>
                <Link className="button button--primary button--lg" to="/conversion-recipes">
                  Conversion Recipes
                </Link>
                <Link className="button button--secondary button--lg" to="/use-as-a-command-line-interface">
                  Command Line
                </Link>
                <Link className="button button--secondary button--lg" to="/download-and-installation">
                  Install
                </Link>
              </div>
            </div>

            <div className={styles.flowCard} aria-label="Convert-Pheno conversion flow">
              <Link className={styles.identity} to="/what-is-convert-pheno">
                <img className={styles.heroLogo} src={logoUrl} alt="Convert-Pheno logo" />
                <span>Convert-Pheno</span>
              </Link>
              <div className={styles.flow}>
                <div>
                  <span>Input</span>
                  <strong>BFF · PXF · OMOP · REDCap · CSV</strong>
                </div>
                <div className={styles.arrow}>→</div>
                <div className={styles.centerModel}>
                  <span>Target model</span>
                  <strong>BFF</strong>
                </div>
                <div className={styles.arrow}>→</div>
                <div>
                  <span>Output</span>
                  <strong>BFF · PXF · OMOP · CSV</strong>
                </div>
              </div>
              <div className={styles.tokens}>
                <span>individuals</span>
                <span>biosamples</span>
                <span>datasets</span>
                <span>cohorts</span>
              </div>
            </div>
          </div>
        </section>

        <section className={styles.sections}>
          <div className={styles.grid}>
            <Link className={styles.card} to="/download-and-installation">
              <span>Setup</span>
              <h2>Install</h2>
              <p>Containerized and non-containerized setup paths, including optional OMOP resources.</p>
            </Link>
            <Link className={styles.card} to="/supported-formats">
              <span>Formats</span>
              <h2>Choose</h2>
              <p>Supported input and output formats, including entity-aware BFF output.</p>
            </Link>
            <Link className={styles.card} to="/conversion-recipes">
              <span>Commands</span>
              <h2>Run the CLI</h2>
              <p>Copy-paste commands for PXF, OMOP-CDM, REDCap, CSV, CDISC-ODM, and BFF conversions.</p>
            </Link>
            <Link className={styles.card} to="/omop-cdm">
              <span>Clinical DB</span>
              <h2>Convert OMOP</h2>
              <p>OMOP-CDM SQL or CSV input to Beacon and Phenopackets outputs.</p>
            </Link>
            <Link className={styles.card} to="/use-as-an-api">
              <span>Developers</span>
              <h2>Call from Code</h2>
              <p>Use the Perl API, Python binding, or HTTP(s) API only when you need programmatic access.</p>
            </Link>
          </div>
        </section>
      </main>
    </Layout>
  );
}
