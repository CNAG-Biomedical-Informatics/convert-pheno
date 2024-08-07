!!! Info "Compatibility"

    The software `Convert-Pheno` can be installed **locally** on the following operating systems:

    | Operating System | Supported Versions            |
    |------------------|-------------------------------|
    | Linux            | All major distributions       |
    | macOS            | macOS 10.14 (Mojave) and later|
    | Windows          | Windows Server OS             |


We provide several alternatives (containerized and non-containerized) for download and installation.

???+ Question "Which download method should I use?"
 
    It depends in which components you want to use and your fluency in performing Docker-based installations. Most people use the [CLI](use-as-a-command-line-interface.md).

    | Use case | Method  |
    | --  | -- |
    | CLI |  1 (CPAN) |
    | CLI (conda) | 2 (CPAN in Conda env)|
    | API | 4 or 5 (Docker) |
    | Web App UI | [Here](https://cnag-biomedical-informatics.github.io/convert-pheno-ui)

## Non-Containerized

=== "Method 1: From CPAN"

    The core of software is a module implemented in `Perl` and it is available in the Comprehensive Perl Archive Network (CPAN). See the description [here](https://metacpan.org/pod/Convert::Pheno).

    With the CPAN distribution you get:

    * Module
    * CLI

    !!! Warning "Linux: Required system-level libraries"

        Before procesing with installation, we will need to install a few system level dependencies:

        * `libbz2-dev:` This is the development library for bzip2, which is used for data compression.

        * `zlib1g-dev:` This is the development library for zlib, which is another data compression library.

        * `libperl-dev:` This package contains the headers and libraries necessary to compile C or C++ programs to link against the Perl library, enabling you to write Perl modules in C or C++.

        * `libssl-dev:` This package is part of OpenSSL, which provides secure socket layer (SSL) capabilities. For SSL/TLS related tasks in Perl, you can use modules such as IO::Socket::SSL or Net::SSLeay, but these modules also require OpenSSL to be installed on the system.

    To install it, plese see this [README](usage.md#method-1-from-cpan).

=== "Method 2: From CPAN in a **Conda** environment"

     With the CPAN distribution you get:

    * Module
    * CLI

    ### Step 1: Install Miniconda

    !!! Warning "Instructions for x86_64"

        The following instructions work for `amd64|x86_64` architectures. If you have a new Mac please use `amd64`.
    
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
    
    Add bioconda channels with the following command:
    
    ```bash
    conda config --add channels bioconda
    ```

    Note: It's recommended to use a new Conda environment when installing new packages to avoid dependency conflicts. You can create and activate a new environment with the following commands:


    ### Step 3: Installation

    ```bash
    conda create -n myenv
    conda activate myenv
    ```

    (Replace myenv with the name you want to give to your environment)

    Then you can to run the following commands:

    ```bash
    conda install -c conda-forge gcc_linux-64 perl perl-app-cpanminus
    #conda install -c bioconda perl-mac-systemdirectory # (MacOS only)
    cpanm --notest Convert::Pheno
    ```

    You can execute `Convert::Pheno` *CLI*  by typing:

    ```bash
    convert-pheno --help
    ```

    To deactivate:
   
    ```
    conda deactivate -n myenv
    ```

    ### Optional: Using Convert::Pheno `Perl` module in `Python`

    First we will download and install `PyPerler`

    ```bash
    git clone https://github.com/tkluck/pyperler
    cd pyperler
    make install 2> install.log
    ```

    Now you should be able to execute this file:

    ```bash
    ~/miniconda3/envs/myenv/lib/perl5/site_perl/auto/share/dist/Convert-Pheno/ex/python.py
    ```

    This is the expected output:
 
    ```json
    {
    "id": "P0007500",
    "sex": {
        "id": "NCIT:C16576",
        "label": "Female"
          }
    }
    ```

    Feel free to copy that file and use for your own purposes.

=== "Method 3: From Github"

    With the non-containerized version from Github you get:

    * Module
    * CLI
    * APIs

    Please follow the instructions provided in this [README](usage.md#method-3-from-github).

## Containerized

With the containerized version you get:

* Module
* CLI
* APIs

=== "Method 4: From Docker Hub"

    Please follow the instructions provided in this [README](usage.md#method-4-from-docker-hub).

=== "Method 5: With Dockerfile"

    Please follow the instructions provided in this [README](usage.md#method-5-with-dockerfile).
