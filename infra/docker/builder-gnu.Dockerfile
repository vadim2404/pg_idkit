# rust:1.73.0-slim-bullseye as of 2023/10/29
FROM rust:1.73.0-slim-bullseye@sha256:9f7ad33ce267070d8982f4503ec83fd0d7cd19c7e30baaa5eb4ac5e26ba23ae1

ENV CARGO_HOME=/usr/local/cargo
ENV CARGO_TARGET_DIR=/usr/local/build/target
ENV SCCACHE_DIR=/usr/local/sccache
# Disable cargo incremental builds since sccache can't support them
ENV CARGO_INCREMENTAL=0

# Install deps
RUN apt update && apt install -y libssl-dev git openssh-client pkg-config curl ca-certificates gnupg wget
RUN cargo install sccache --locked

ENV CARGO_BUILD_RUSTC_WRAPPER=/usr/local/cargo/bin/sccache

##################
# Setup Postgres #
##################

# Add postgresql.org PGP keys
RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add

# Add postgres repo
RUN sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt bullseye-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

# Install pg15
RUN apt -y update && apt -y upgrade && apt install -y postgresql-15

# Install NodeJS
RUN set -uex; \
    apt-get update; \
    apt-get install -y ca-certificates curl gnupg; \
    mkdir -p /etc/apt/keyrings; \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
     | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg; \
    NODE_MAJOR=20; \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" \
     > /etc/apt/sources.list.d/nodesource.list; \
    apt-get update; \
    apt-get install nodejs -y;

# Install dependencies for building postgres, NodeJS, etc
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates \
    git build-essential libpq-dev \
    postgresql postgresql-server-dev-15 \
    curl libreadline6-dev zlib1g-dev libclang-dev \
    pkg-config cmake nodejs

# Add postgres user to root group
RUN useradd --user-group --system --create-home --no-log-init idkit && \
    usermod -aG sudo idkit && \
    chown -R idkit /home/idkit && \
    addgroup idkit root

# Allow writing to postgres extensions folder
RUN chmod g+w -R /usr/share/postgresql/**/extension && \
    chmod g+w -R /usr/lib/postgresql/**/lib

###############
# Setup Cargo #
###############

# Allow writing to cargo cache by idkit (now part of root group)
RUN chmod g+w -R /usr/local/cargo
RUN chmod g+w -R /usr/local/build

RUN mkdir /usr/local/sccache
RUN chmod g+w -R /usr/local/sccache

# Install & Initialize pgrx
# NOTE: pgrx must be reinitialized if cargo-pgrx changes
RUN su idkit -c "cargo install cargo-pgrx@0.11.0"
RUN su idkit -c "cargo pgrx init --pg15 download"

# Install development/build/testing deps
RUN su idkit -c "cargo install just sccache cargo-cache cargo-get cargo-edit"
