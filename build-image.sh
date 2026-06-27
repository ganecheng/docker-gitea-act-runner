#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com)
# SPDX-FileContributor: Sebastian Thomschke
# SPDX-License-Identifier: Apache-2.0
# SPDX-ArtifactOfProjectHomePage: https://github.com/vegardit/docker-gitea-act-runner

shared_lib="$(dirname "${BASH_SOURCE[0]}")/.shared"
[[ -e $shared_lib ]] || curl -sSfL "https://raw.githubusercontent.com/vegardit/docker-shared/v1/download.sh?_=$(date +%s)" | bash -s v1 "$shared_lib" || exit 1
# shellcheck disable=SC1091  # Not following: $shared_lib/lib/build-image-init.sh was not specified as input
source "$shared_lib/lib/build-image-init.sh"


#################################################
# declare image meta
#################################################
gitea_runner_version=${GITEA_RUNNER_VERSION:-latest}
image_repo=${DOCKER_IMAGE_REPO:-vegardit/gitea-act-runner}
base_image=${DOCKER_BASE_IMAGE:-ubuntu:24.04}

declare -A image_meta=(
  [authors]="Vegard IT GmbH (vegardit.com)"
  [title]="$image_repo"
  [description]="Docker image based on ubuntu:24.04 to run Gitea's action runner as a Docker container"
  [source]="$(git config --get remote.origin.url)"
  [revision]="$(git rev-parse --short HEAD)"
  [version]="$(git rev-parse --short HEAD)"
  [created]="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
)


#################################################
# resolve gitea act runner version
#################################################
case $gitea_runner_version in
  latest) gitea_runner_effective_version=$(curl -sSf 'https://gitea.com/api/v1/repos/gitea/runner/releases?draft=false&pre-release=false&limit=1' | jq -r '.[0].tag_name | ltrimstr("v")') ;;
  *)      gitea_runner_effective_version=$gitea_runner_version ;;
esac


#################################################
# define tags
#################################################
declare -a tags=()
tags+=("${DOCKER_IMAGE_TAG_PREFIX:-}$gitea_runner_version")
tags+=("${DOCKER_IMAGE_TAG_PREFIX:-}$gitea_runner_effective_version")


#################################################
# prepare docker
#################################################
run_step -- docker version

export DOCKER_BUILDKIT=1


#################################################
# build the image
#################################################
image_name=$image_repo:${tags[0]}

# shellcheck disable=SC2154  # base_layer_cache_key is referenced but not assigned
build_opts=(
  --file "image/Dockerfile"
  --progress=plain
  --pull
  --build-arg BASE_LAYER_CACHE_KEY="$base_layer_cache_key"
  --build-arg BASE_IMAGE="$base_image"
  --build-arg GIT_BRANCH="${GIT_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
  --build-arg GIT_COMMIT_DATE="$(date -d "@$(git log -1 --format='%at')" --utc +'%Y-%m-%d %H:%M:%S UTC')"
  --build-arg GITEA_RUNNER_VERSION="$gitea_runner_effective_version"
  --build-arg FLAVOR="$DOCKER_IMAGE_FLAVOR"
  --build-arg INSTALL_SUPPORT_TOOLS="${INSTALL_SUPPORT_TOOLS:-0}"
)

for key in "${!image_meta[@]}"; do
  build_opts+=(--build-arg "OCI_${key}=${image_meta[$key]}")
done

if [[ -n ${GITHUB_TOKEN:-} ]]; then
  build_opts+=(--secret "id=github_token,env=GITHUB_TOKEN")
fi

if [[ $OSTYPE == "cygwin" || $OSTYPE == "msys" ]]; then
  project_root=$(cygpath -w "$project_root")
fi

run_step "Building docker image [$image_name]..." -- \
  docker build "${build_opts[@]}" -t "$image_name" "$project_root"


#################################################
# perform security audit
#################################################
if [[ ${DOCKER_AUDIT_IMAGE:-1} == "1" ]]; then
  run_step "Auditing docker image [$image_name]" -- \
    bash "$shared_lib/cmd/audit-image.sh" "$image_name"
fi


#################################################
# test image
#################################################
run_step "Testing docker image [$image_name]" -- \
  docker run --pull=never --rm "$image_name" gitea-runner --version


#################################################
# push image
#################################################
if [[ ${DOCKER_PUSH:-} == "true" ]]; then
  for tag in "${tags[@]}"; do
    run_step "Tagging [$image_name] -> [$image_repo:$tag]" -- docker tag "$image_name" "$image_repo:$tag"
    run_step "Pushing [docker.io/$image_repo:$tag]" -- docker push "$image_repo:$tag"
  done
fi
if [[ ${DOCKER_PUSH_GHCR:-} == "true" ]]; then
  for tag in "${tags[@]}"; do
    ghcr_image="ghcr.io/$image_repo:$tag"
    run_step "Tagging [$image_name] -> [$ghcr_image]" -- docker tag "$image_name" "$ghcr_image"
    run_step "Pushing [$ghcr_image]" -- docker push "$ghcr_image"
  done
fi
if [[ ${DOCKER_PUSH_SWR:-} == "true" ]]; then
  swr_registry=${DOCKER_SWR_REGISTRY:-swr.cn-southwest-2.myhuaweicloud.com}
  swr_namespace=${DOCKER_SWR_NAMESPACE:-gsc-hub}
  swr_image_name="${image_repo##*/}"
  for tag in "${tags[@]}"; do
    swr_image="$swr_registry/$swr_namespace/$swr_image_name:$tag"
    run_step "Tagging [$image_name] -> [$swr_image]" -- docker tag "$image_name" "$swr_image"
    run_step "Pushing [$swr_image]" -- docker push "$swr_image"
  done
fi
