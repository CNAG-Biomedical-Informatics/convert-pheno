FROM ubuntu:22.04

ARG BUILD_VERSION=dev
ARG VCS_REF=unknown

LABEL maintainer="Manuel Rueda <manuel.rueda@cnag.eu>" \
      org.opencontainers.image.title="Convert-Pheno" \
      org.opencontainers.image.description="Clinical and phenotypic data model converter" \
      org.opencontainers.image.source="https://github.com/CNAG-Biomedical-Informatics/convert-pheno" \
      org.opencontainers.image.version="${BUILD_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.licenses="Artistic-2.0"

# Install Linux tools
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends \
       gcc unzip make git cpanminus perl-doc vim sudo libbz2-dev libexpat1-dev \
       zlib1g-dev libperl-dev libssl-dev python3-pip \
    && pip3 install --no-cache-dir setuptools "fastapi[all]" \
    && rm -rf /var/lib/apt/lists/*

# Install dependencies before copying the source so this layer survives code changes.
WORKDIR /usr/share/convert-pheno
# Cpanel::JSON::XS 4.52's ARM NEON code uses mixed declarations, but its
# Perl 5.34 build flags make these fatal. Keep warnings, relaxing only this
# diagnostic for this dependency; do not change flags for other modules.
RUN if [ "$(uname -m)" = aarch64 ]; then \
      cpanm --notest --configure-timeout 300 \
        --configure-args='DEFINE="-Wall -Wextra -W -Wno-error=declaration-after-statement"' \
        R/RU/RURBAN/Cpanel-JSON-XS-4.52.tar.gz \
        || { status=$?; cat /root/.cpanm/work/*/build.log; exit "$status"; }; \
    fi
COPY cpanfile ./
# ARM emulation can make otherwise valid configure steps exceed cpanm's 60s default.
RUN cpanm --notest --configure-timeout 300 --installdeps . \
    || { status=$?; cat /root/.cpanm/work/*/build.log; exit "$status"; }

# Build from the caller-supplied checkout so tags and workflow refs are reproducible.
COPY . .
ENV PATH="/usr/share/convert-pheno/bin:${PATH}"

# Add user "dockeruser"
ARG UID=1000
ARG GID=1000

RUN groupadd -g "${GID}" dockeruser \
  && useradd --create-home --no-log-init -u "${UID}" -g "${GID}" dockeruser

# To change default user from root -> dockeruser
#USER dockeruser

WORKDIR /usr/share/convert-pheno

CMD ["convert-pheno", "--help"]
