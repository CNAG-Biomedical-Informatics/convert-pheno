!!! Info "Where should I install it?"
    `Convert-Pheno` is a software that must be installed **locally** in a Linux server/workstation. 

We provide several alternatives (containerized and non-containerized) for download and installation.

## Containerized (Recommended Method)

=== "Method 1: From Docker Hub"

    Please follow the instructions provided in this [README](https://github.com/cnag-biomedical-informatics/convert-pheno#method-1-from-docker-hub).

=== "Method 2: With Dockerfile"

    Please follow the instructions provided in this [README](https://github.com/cnag-biomedical-informatics/convert-pheno#method-2-with-dockerfile).

## Non-Containerized

=== "Method 3: From Github"

    Please follow the instructions provided in this [README](https://github.com/cnag-biomedical-informatics/convert-pheno#non-containerized).

=== "Method 4: From CPAN"

    The core of software is a module implemented in `Perl` and it is available in the Comprehensive Perl Archive Network (CPAN). See the description [here](https://metacpan.org/pod/Convert::Pheno). Along with the module, you'll get the [CLI](use-as-a-command-line-interface.md).

    !!! Warning "Required system-level libraries"

        Before procesing with installation, we will need to install a few system level dependencies:

        * `libbz2-dev:` This is the development library for bzip2, which is used for data compression.

        * `zlib1g-dev:` This is the development library for zlib, which is another data compression library.

        * `libperl-dev:` This package contains the headers and libraries necessary to compile C or C++ programs to link against the Perl library, enabling you to write Perl modules in C or C++.

        * `libssl-dev:` This package is part of OpenSSL, which provides secure socket layer (SSL) capabilities. For SSL/TLS related tasks in Perl, you can use modules such as IO::Socket::SSL or Net::SSLeay, but these modules also require OpenSSL to be installed on the system.

    To install it, we'll be using `cpanminus` (with sudo privileges):

        sudo apt-get install cpanminus libbz2-dev zlib1g-dev libperl-dev libssl-dev

    Then, to install the module (system level):

        cpanm --sudo Convert::Pheno

    Alternatively, if you want to peform a local installation:

        cpanm --sudo Carton # sys-level
        echo "requires 'Convert::Pheno'" > cpanfile
        carton install
        carton exec -- convert-pheno

=== "Method 5: From BioConda"

    TBA
