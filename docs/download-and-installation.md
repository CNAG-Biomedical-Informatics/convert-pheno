# Summary

`Convert-Pheno` is a software that must be installed **locally** in a Linux server/workstation. 

We provide several alternatives for download and installation.

## Method 1: From CPAN

!!! Danger "Disclaimer"
    This installation method will be available once the paper is accepted.

The software is implemented in `Perl` language and packaged as a Perl Module in the Comprehensive Perl Archive Network (CPAN). See the description [here](https://metacpan.org/pod/Convert::Pheno).

To install it, we'll be using `cpanminus` (with sudo privileges):

    sudo apt-get install cpanminus

Then the install the module:

  cpanm --sudo Convert::Pheno

## Method 2: Containerized

Please follow the instructions provided in this [README](https://github.com/mrueda/convert-pheno#containerized).

## Method 3: Non-containerized

Please follow the instructions provided in this [README](https://github.com/mrueda/convert-pheno#non-containerized).

