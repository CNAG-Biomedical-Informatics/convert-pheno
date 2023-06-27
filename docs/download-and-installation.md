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

=== "Method 4: From BioConda"

    TBA

=== "Method 5: From CPAN"

    The core of software is a module implemented in `Perl` and it is available in the Comprehensive Perl Archive Network (CPAN). See the description [here](https://metacpan.org/pod/Convert::Pheno). Along with the module, you'll get the [CLI](use-as-a-command-line-interface.md).

    !!! Warning "Required system-level libraries"

        Before procesing with installation, we will need to install a few system level dependencies:

        * `libbz2-dev:` This is the development library for bzip2, which is used for data compression. There is no direct CPAN replacement, but Perl does have modules for handling bzip2 compressed data, such as IO::Compress::Bzip2 and Compress::Bzip2. However, these modules still rely on the system having the necessary libraries.

        * `zlib1g-dev:` This is the development library for zlib, which is another data compression library. Similar to bzip2, Perl has modules for zlib compression and decompression like Compress::Zlib, IO::Compress::Gzip, and IO::Uncompress::Gunzip. But these also depend on the system's zlib library.

        * `libperl-dev:` This package contains the headers and libraries necessary to compile C or C++ programs to link against the Perl library, enabling you to write Perl modules in C or C++. There is no CPAN alternative for this.

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
