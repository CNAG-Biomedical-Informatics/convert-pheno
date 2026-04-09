!!! Info "Compatibility"

    The software `Convert-Pheno` can be installed **locally** on the following operating systems:

    | Operating System | Supported Versions            |
    |------------------|-------------------------------|
    | Linux            | All major distributions       |
    | macOS            | macOS 10.14 (Mojave) and later|
    | Windows          | Windows Server OS             |

We provide several alternatives for download and installation.

???+ Question "Which download method should I use?"

    It depends on which components you want to use and your familiarity with Docker-based installations. Most users work with the [CLI](use-as-a-command-line-interface.md).

    | Use case | Recommended path |
    | -- | -- |
    | CLI | Non-containerized (CPAN) |
    | CLI in Conda | Non-containerized (Conda) |
    | API | Docker |
    | Web App UI | [Convert-Pheno UI](https://cnag-biomedical-informatics.github.io/convert-pheno-ui) |

## Non-Containerized

Use this path when you want to run `convert-pheno` directly from CPAN, GitHub, Conda, or your own Perl environment.

Detailed instructions:

- [non-containerized/README.md](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/non-containerized/README.md)

## Containerized

Use this path when you want a reproducible environment with the dependencies preinstalled, especially for API usage.

Detailed instructions:

- [docker/README.md](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/blob/main/docker/README.md)
