import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import useBaseUrl from '@docusaurus/useBaseUrl';
import styles from './index.module.css';

export default function Home() {
  const logoUrl = useBaseUrl('/img/CP-logo.png');
  const wordmarkUrl = useBaseUrl('/img/CP-text.png');

  return (
    <Layout
      title="Convert-Pheno"
      description="A toolkit for interconverting clinical and phenotypic data models">
      <main>
        <section className={styles.hero}>
          <div className={styles.heroInner}>
            <Link className={styles.identity} to="/what-is-convert-pheno">
              <img className={styles.heroLogo} src={logoUrl} alt="Convert-Pheno logo" />
              <img className={styles.heroWordmark} src={wordmarkUrl} alt="Convert-Pheno" />
            </Link>
            <h1 className={styles.srOnly}>Convert-Pheno</h1>
            <p className={styles.heroSubtitle}>
              An open-source toolkit for converting clinical and phenotypic data
              between Beacon v2 Models, Phenopackets v2, OMOP-CDM, REDCap,
              CDISC-ODM, CSV, and related exchange formats.
            </p>
            <div className={styles.actions}>
              <Link className="button button--primary button--lg" to="/what-is-convert-pheno">
                Start Here
              </Link>
              <Link className="button button--secondary button--lg" to="/choose-an-interface">
                Choose Interface
              </Link>
              <Link className="button button--secondary button--lg" to="/use-as-a-command-line-interface">
                Run the CLI
              </Link>
            </div>
          </div>
        </section>

        <section className={styles.sections}>
          <div className={styles.grid}>
            <Link className={styles.card} to="/download-and-installation">
              <h2>Install</h2>
              <p>Containerized and non-containerized setup paths, including optional OMOP resources.</p>
            </Link>
            <Link className={styles.card} to="/supported-formats">
              <h2>Choose</h2>
              <p>Supported input and output formats, including entity-aware BFF output.</p>
            </Link>
            <Link className={styles.card} to="/conversion-recipes">
              <h2>Recipes</h2>
              <p>Copy-paste commands for PXF, OMOP-CDM, REDCap, CSV, CDISC-ODM, and BFF workflows.</p>
            </Link>
            <Link className={styles.card} to="/omop-cdm">
              <h2>Convert OMOP</h2>
              <p>OMOP-CDM SQL or CSV input to Beacon and Phenopackets outputs.</p>
            </Link>
            <Link className={styles.card} to="/use-as-an-api">
              <h2>Integrate</h2>
              <p>Use the module, HTTP API, Python bridge, or JavaScript fetch examples.</p>
            </Link>
          </div>
        </section>
      </main>
    </Layout>
  );
}
