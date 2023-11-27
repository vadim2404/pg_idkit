cargo := env_var_or_default("CARGO", "cargo")
cargo_get := env_var_or_default("CARGO_GET", "cargo-get")
cargo_watch := env_var_or_default("CARGO_WATCH", "cargo-watch")
docker := env_var_or_default("DOCKER", "docker")
git := env_var_or_default("GIT", "git")
just := env_var_or_default("JUST", just_executable())

changelog_path := "CHANGELOG"

default:
    {{just}} --list

###########
# Tooling #
###########

_check-installed-version tool msg:
    #!/usr/bin/env -S bash -euo pipefail
    if [ -z "$(command -v {{tool}})" ]; then
      echo "{{msg}}";
      exit 1;
    fi

@_check-tool-cargo:
    {{just}} _check-installed-version {{cargo}} "'cargo' not available, please install the Rust toolchain (see: https://github.com/rust-lang/cargo/)";

@_check-tool-cargo-watch:
    {{just}} _check-installed-version {{cargo_watch}} "'cargo-watch' not available, please install cargo-watch (https://github.com/passcod/cargo-watch)"

@_check-tool-cargo-get:
    {{just}} _check-installed-version {{cargo_get}} "'cargo-get' not available, please install cargo-get (https://crates.io/crates/cargo-get)"

#########
# Build #
#########

version := `cargo get package.version`
revision := `git rev-parse --short HEAD`

# NOTE: we can't use this as the official version getter until
# see: https://github.com/nicolaiunrein/cargo-get/issues/14
@get-version: _check-tool-cargo-get
    cargo get package.version

@get-revision: _check-tool-cargo-get
    echo -n {{revision}}

print-version:
    #!/usr/bin/env -S bash -euo pipefail
    echo -n `{{just}} get-version`

print-revision:
    #!/usr/bin/env -S bash -euo pipefail
    echo -n `{{just}} get-revision`

changelog:
    {{git}} cliff --unreleased --tag=$(VERSION) --prepend=$(CHANGELOG_FILE_PATH)

build:
    {{cargo}} build

build-watch: _check-tool-cargo _check-tool-cargo-watch
    {{cargo_watch}} -x "build $(CARGO_BUILD_FLAGS)" --watch src

build-test-watch: _check-tool-cargo _check-tool-cargo-watch
    {{cargo_watch}} -x "test $(CARGO_BUILD_FLAGS)" --watch src

pkg_pg_version := env_var_or_default("PKG_PG_VERSION", "15.5")
pkg_pg_config_path := env_var_or_default("PKG_PG_CONFIG_PATH", "~/.pgrx/" + pkg_pg_version + "/pgrx-install/bin/pg_config")

package:
    {{cargo}} pgrx package --pg-config {{pkg_pg_config_path}}

test:
    {{cargo}} test
    {{cargo}} pgrx test

##########
# Docker #
##########

container_img_arch := env_var_or_default("CONTAINER_IMAGE_ARCH", "amd64")

pg_image_version := env_var_or_default("POSTGRES_IMAGE_VERSION", "15.5")
pg_os_image_version := env_var_or_default("POSTGRES_OS_IMAGE_VERSION", "alpine3.18")

pgidkit_image_name := env_var_or_default("PGIDKIT_IMAGE_NAME", "ghcr.io/vadosware/pg_idkit")
pgidkit_image_tag := env_var_or_default("POSGRES_IMAGE_VERSION", version + "-" + "pg" + pg_image_version + "-" + pg_os_image_version + "-" + container_img_arch)
pgidkit_image_name_full := env_var_or_default("PGIDKIT_IMAGE_NAME_FULL", pgidkit_image_name + ":" + pgidkit_image_tag)
pgidkit_dockerfile_path := env_var_or_default("PGIDKIT_DOCKERFILE_PATH", "infra" / "docker" / pgidkit_image_tag + ".Dockerfile")

docker_password_path := env_var_or_default("DOCKER_PASSWORD_PATH", "secrets/docker/password.secret")
docker_username_path := env_var_or_default("DOCKER_USERNAME_PATH", "secrets/docker/username.secret")
docker_image_registry := env_var_or_default("DOCKER_IMAGE_REGISTRY", "ghcr.io/vadosware/pg_idkit")
docker_config_dir := env_var_or_default("DOCKER_CONFIG", "secrets/docker")

img_dockerfile_path := "infra" / "docker" / "pg" + pg_image_version + "-" + pg_os_image_version + "-" + container_img_arch + ".Dockerfile"

# Ensure that that a given file is present
_ensure-file file:
    #!/usr/bin/env -S bash -euo pipefail
    @if [ ! -f "{{file}}" ]; then
      echo "[error] file [{{file}}] is required, but missing";
      exit 1;
    fi;

# Log in with docker using local credentials
docker-login:
    {{just}} ensure-file {{docker_password_path}}
    {{just}} ensure-file {{docker_username_path}}
    cat {{docker_password_path}} | {{docker}} login {{docker_image_registry}} -u `cat {{docker_username_path}}` --password-stdin
    cp {{docker_config_dir}}/config.json {{docker_config_dir}}/.dockerconfigjson

docker_platform_arg := env_var_or_default("DOCKER_PLATFORM_ARG", "")
docker_progress_arg := env_var_or_default("DOCKER_PROGRESS_ARG", "")

#####################
# Docker Image - ci #
#####################
#
# This image is used as a cache for speeding up CI builds
#

ci_dockerfile_path := env_var_or_default("CI_DOCKERFILE_PATH", "infra" / "docker" / "ci.Dockerfile")
ci_image_name := env_var_or_default("CI_IMAGE_NAME", "ghcr.io/vadosware/pg_idkit/builder")
ci_image_tag := env_var_or_default("CI_IMAGE_TAG", "0.1.x")
ci_image_name_full := env_var_or_default("CI_IMAGE_NAME_FULL", ci_image_name + ":" + ci_image_tag)

# Build the docker image used in CI
build-ci-image:
    {{docker}} build -f {{ci_dockerfile_path}} -t {{ci_image_name_full}} .

# Push the docker image used in CI (to GitHub Container Registry)
push-ci-image:
    {{docker}} push {{ci_image_name_full}}

###########################
# Docker Image - base-pkg #
###########################
#
# This image is used as a base for packaging flows, usually while building
# the end-user facing Docker image that is contains Postgres & pg_idkit
#

# Determine the Dockerfile to use when building the packaging utility base image
base_pkg_dockerfile_path := if pg_os_image_version == "alpine3.18" {
  "infra/docker/base-pkg-alpine3.18.Dockerfile"
} else if pg_os_image_version == "bookworm" {
  "infra/docker/base-pkg-bookworm.Dockerfile"
} else {
  error("invalid pg_os_image_version")
}
base_pkg_image_name := env_var_or_default("PKG_IMAGE_NAME", "ghcr.io/vadosware/pg_idkit/base-pkg")
base_pkg_version := env_var_or_default("PKG_IMAGE_NAME", "0.1.x")
base_pkg_image_tag := env_var_or_default("POSGRES_IMAGE_VERSION", base_pkg_version + "-" + "pg" + pg_image_version + "-" + pg_os_image_version + "-" + container_img_arch)
base_pkg_image_name_full := env_var_or_default("PKG_IMAGE_NAME_FULL", base_pkg_image_name + ":" + base_pkg_image_tag)

# Build the base image for packaging
build-base-pkg-image:
      {{docker}} build -f {{base_pkg_dockerfile_path}} . -t {{base_pkg_image_name_full}};

# Push the base image for packaging
push-base-pkg-image:
      {{docker}} push {{base_pkg_image_name_full}}

###########################
# Docker Image - pg_idkit #
###########################
#
# This image is the pg_idkit image itself, normally built FROM
# a image of base-pkg
#

# Build the docker image for pg_idkit
build-image:
    {{docker}} build {{docker_platform_arg}} {{docker_progress_arg}} -f {{img_dockerfile_path}} -t {{pgidkit_image_name_full}} --build-arg PGIDKIT_REVISION={{revision}} --build-arg PGIDKIT_VERSION={{pgidkit_image_tag}} .

# Push the docker image for pg_idkit
push-image:
    {{docker}} push {{pgidkit_image_name_full}}