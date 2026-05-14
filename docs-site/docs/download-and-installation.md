---
title: Download & Installation
sidebar_label: Download & Installation
slug: /download-and-installation
---

import Link from '@docusaurus/Link';

:::info[Compatibility]

The software `Convert-Pheno` can be installed **locally** on the following operating systems:

| Operating System | Supported Versions            |
|------------------|-------------------------------|
| Linux            | All major distributions       |
| macOS            | macOS 10.14 (Mojave) and later|
| Windows          | Windows Server OS             |

:::
<div className="convertQuickHero">
  <p className="convertEyebrow">Installation</p>
  <h2>Choose the setup that matches how you will run the converter.</h2>
  <p>
    Most command-line users can install locally. Docker is the recommended
    route for API usage and reproducible execution environments.
  </p>
</div>

<div className="convertInstallGrid">
  <Link className="convertInstallCard" to="/download-and-installation/non-containerized">
    <span className="convertCardLabel">Local</span>
    <h3>Non-containerized installation</h3>
    <p>Use CPAN, GitHub, Conda, or an existing Perl environment to run `convert-pheno` directly.</p>
  </Link>
  <Link className="convertInstallCard" to="/download-and-installation/docker-based">
    <span className="convertCardLabel">Container</span>
    <h3>Docker installation</h3>
    <p>Use a prebuilt environment for the HTTP(s) API, deployments, and reproducible runs.</p>
  </Link>
</div>

<details className="convertSetupDetails">
<summary>Which download method should I use?</summary>


It depends on which components you want to use and your familiarity with Docker-based installations. Most users work with the [CLI](use-as-a-command-line-interface).

| Use case | Recommended path |
| -- | -- |
| CLI | Non-containerized (CPAN) |
| CLI in Conda | Non-containerized (Conda) |
| API | Docker |
| Web App UI | Display and exploration only; the deployed UI currently uses an older Convert-Pheno version |

</details>
## Non-Containerized

Use this path when you want to run `convert-pheno` directly from CPAN, GitHub, Conda, or your own Perl environment.

Detailed instructions:

- [Non-Containerized Installation](download-and-installation/non-containerized)

## Containerized

Use this path when you want a reproducible environment with the dependencies preinstalled, especially for API usage.

Detailed instructions:

- [Docker Installation](download-and-installation/docker-based)
