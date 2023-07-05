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

    To install it, plese see this [README](https://github.com/CNAG-Biomedical-Informatics/convert-pheno#from-cpan).

=== "Method 5: From Bioconda"

    These are the steps for installing [Convert-Pheno Bioconda Package](https://github.com/bioconda/bioconda-recipes/tree/master/recipes/convert-pheno) in Ubuntu.
    
    
    ### Step 1: Install Miniconda
    
    1. Download the Miniconda installer for Linux with the following command:
    
        ```bash
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
        ```
    
    2. Run the installer:
    
        ```bash
        bash Miniconda3-latest-Linux-x86_64.sh
        ```
    
        Follow the prompts on the installer screens.
    
    3. Close and re-open your terminal window for the installation to take effect.
    
    ### Step 2: Set Up Channels
    
    Once you have Conda installed, set up the channels. Bioconda depends on the `conda-forge` and `defaults` channel.
    
    Add these channels with the following commands:
    
    ```bash
    conda config --add channels defaults
    conda config --add channels bioconda
    conda config --add channels conda-forge
    ```

    Note: It's recommended to use a new Conda environment when installing new packages to avoid dependency conflicts. You can create and activate a new environment with the following commands:


    ```bash
    conda create -n myenv
    conda activate myenv
    ```

    Replace myenv with the name you want to give to your environment.

    Then you can install your package in the myenv environment:

    `conda install -n myenv convert-pheno`
