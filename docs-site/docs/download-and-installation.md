---
title: Download & Installation
sidebar_label: Download & Installation
slug: /download-and-installation
---

import Link from '@docusaurus/Link';

:::info[CLI compatibility]

The command-line interface can be installed on the following operating systems:

| Operating System | Supported Versions                                      |
|------------------|---------------------------------------------------------|
| Linux            | All major distributions                                 |
| macOS            | macOS 10.14 (Mojave) and later                          |
| Windows          | CI-tested with Strawberry Perl 5.40 and 5.42            |

:::
Choose the installation for the interface you intend to use. **Non-containerized
and Docker installations are command-line environments**; Docker can also run
the HTTP(s) API. The Desktop Application has separate native installers that
include a private Perl runtime.

<div className="convertInstallGrid">
  <Link className="convertInstallCard" to="/download-and-installation/non-containerized">
    <span className="convertCardLabel">CLI · Local</span>
    <h3>Non-containerized CLI</h3>
    <p>Use CPAN, GitHub, Conda, or an existing Perl environment to run `convert-pheno` directly.</p>
  </Link>
  <Link className="convertInstallCard" to="/download-and-installation/docker-based">
    <span className="convertCardLabel">CLI · Container</span>
    <h3>Docker CLI</h3>
    <p>Use a prebuilt command-line environment for reproducible conversions or the HTTP(s) API.</p>
  </Link>
  <Link className="convertInstallCard" to="/graphical-interface">
    <span className="convertCardLabel">Desktop</span>
    <h3>Desktop application</h3>
    <p>Use the native Linux, macOS, or Windows interface available from version 0.35.</p>
  </Link>
</div>

<details className="convertSetupDetails">
<summary>Which download method should I use?</summary>


| Use case | Recommended path |
| -- | -- |
| CLI on Linux or macOS | Non-containerized (CPAN) or Docker |
| CLI in Conda | Non-containerized (Conda) |
| CLI on Windows | Docker; native Strawberry Perl is also supported |
| Desktop application | Native installer |
| API | Docker |

</details>
## CLI: Non-Containerized {#non-containerized}

Install locally to run `convert-pheno` directly from CPAN, GitHub, Conda, or an
existing Perl environment.

Detailed instructions:

- [Non-Containerized Installation](download-and-installation/non-containerized)

## CLI: Docker {#containerized}

Use Docker for a prebuilt CLI or API environment with the runtime dependencies
installed. The Docker image does not contain the Desktop Application.

Detailed instructions:

- [Docker Installation](download-and-installation/docker-based)

## Desktop Application

The native application includes the core engine and its runtime; no separate
CPAN installation is needed. See [Desktop Application](graphical-interface) for
downloads, platform requirements, and first-launch instructions.
