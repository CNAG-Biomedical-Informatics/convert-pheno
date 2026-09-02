---
title: Download & Installation
sidebar_label: Download & Installation
slug: /download-and-installation
---

import Link from '@docusaurus/Link';

:::info[Compatibility]

`Convert-Pheno` can be installed locally on the following operating systems:

| Operating System | Supported Versions                                      |
|------------------|---------------------------------------------------------|
| Linux            | All major distributions                                 |
| macOS            | macOS 10.14 (Mojave) and later                          |
| Windows          | CI-tested with Strawberry Perl 5.40 and 5.42            |

:::
Most command-line users can install from CPAN. Docker is the simplest option
for the **Workbench** (available from Convert-Pheno 0.35), and is also useful on
Windows or when the same runtime environment must be reproduced elsewhere.

<div className="convertInstallGrid">
  <Link className="convertInstallCard" to="/download-and-installation/non-containerized">
    <span className="convertCardLabel">Local</span>
    <h3>Non-containerized installation</h3>
    <p>Use CPAN, GitHub, Conda, or an existing Perl environment to run `convert-pheno` directly.</p>
  </Link>
  <Link className="convertInstallCard" to="/download-and-installation/docker-based">
    <span className="convertCardLabel">Container</span>
    <h3>Docker installation</h3>
    <p>Use the Workbench or a prebuilt environment for the HTTP(s) API and reproducible runs.</p>
  </Link>
</div>

<details className="convertSetupDetails">
<summary>Which download method should I use?</summary>


| Use case | Recommended path |
| -- | -- |
| CLI | Non-containerized (CPAN) |
| CLI in Conda | Non-containerized (Conda) |
| CLI on Windows | Docker; native Strawberry Perl is also supported |
| Workbench | Docker |
| API | Docker |

</details>
## Non-Containerized

Install locally to run `convert-pheno` directly from CPAN, GitHub, Conda, or an
existing Perl environment.

Detailed instructions:

- [Non-Containerized Installation](download-and-installation/non-containerized)

## Containerized

Use Docker for the Workbench or for a prebuilt environment with the runtime
dependencies installed.

Detailed instructions:

- [Docker Installation](download-and-installation/docker-based)
