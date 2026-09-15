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
Most command-line users can install from CPAN. Docker provides a reproducible
CLI or API environment. From version 0.35, native desktop installers package the
graphical application and its private Perl runtime.

<div className="convertInstallGrid">
  <Link className="convertInstallCard" to="/download-and-installation/non-containerized">
    <span className="convertCardLabel">Local</span>
    <h3>Non-containerized installation</h3>
    <p>Use CPAN, GitHub, Conda, or an existing Perl environment to run `convert-pheno` directly.</p>
  </Link>
  <Link className="convertInstallCard" to="/download-and-installation/docker-based">
    <span className="convertCardLabel">Container</span>
    <h3>Docker installation</h3>
    <p>Use a prebuilt environment for CLI conversions, the HTTP(s) API, and reproducible runs.</p>
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
| CLI | Non-containerized (CPAN) |
| CLI in Conda | Non-containerized (Conda) |
| CLI on Windows | Docker; native Strawberry Perl is also supported |
| Desktop application | Native installer |
| API | Docker |

</details>
## Non-Containerized

Install locally to run `convert-pheno` directly from CPAN, GitHub, Conda, or an
existing Perl environment.

Detailed instructions:

- [Non-Containerized Installation](download-and-installation/non-containerized)

## Containerized

Use Docker for a prebuilt CLI or API environment with the runtime dependencies
installed.

Detailed instructions:

- [Docker Installation](download-and-installation/docker-based)

## Desktop Application

The native application includes its own Perl runtime and does not require a
separate CPAN installation. See [Desktop Application](graphical-interface) for
platform coverage and pre-release availability.
