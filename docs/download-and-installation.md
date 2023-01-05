!!! Info "Where should I install it?"
    `Convert-Pheno` is a software that must be installed **locally** in a Linux server/workstation. 

We provide several alternatives (containerized and non-containerized) for download and installation.

## Containerized

=== "Method 1: With Dockerfile"

    Please follow the instructions provided in this [README](https://github.com/mrueda/convert-pheno#containerized).

=== "Method 2: From Docker Hub"

    TBA

## Non-Containerized

=== "Method 3: From Github"

    Please follow the instructions provided in this [README](https://github.com/mrueda/convert-pheno#non-containerized).

=== "Method 4: From CPAN"

    !!! Danger "Disclaimer"
        This installation method will be available once the paper is accepted.

    The software is implemented in `Perl` language and packaged as a Perl Module in the Comprehensive Perl Archive Network (CPAN). See the description [here](https://metacpan.org/pod/Convert::Pheno).

    To install it, we'll be using `cpanminus` (with sudo privileges):

        sudo apt-get install cpanminus

    Then the install the module:

        cpanm --sudo Convert::Pheno
