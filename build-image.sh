#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com)
# SPDX-FileContributor: Sebastian Thomschke
# SPDX-License-Identifier: Apache-2.0
# SPDX-ArtifactOfProjectHomePage: https://github.com/vegardit/docker-gitea-act-runner

set -euo pipefail

project_root="$(readlink -e "$(dirname "${BASH_SOURCE[0]}")")"


#################################################
# helper functions
#################################################
function run_step() {
  local title=""
  while [[ ${1:-} != "--" ]]; do
    title="$1"
    shift
  done
  shift  # remove "--"
  if [[ -n $title ]]; then
    echo ""
    echo "==========================================================="
    echo "$title"
    echo "==========================================================="
  fi
  echo "+ $*"
  "$@"
}

function push_to_registry() {
  local target_prefix="$1"
  for tag in "${tags[@]}"; do
    local target="$target_prefix:$tag"
    docker history "$target"
    run_step "Tagging [$image_name] -> [$target]" -- docker tag "$image_name" "$target"
    run_step "Pushing [$target]" -- docker push "$target"
  done
}


#################################################
# configuration
#################################################
image_repo=${DOCKER_IMAGE_REPO:-vegardit/gitea-act-runner}
base_image=${DOCKER_BASE_IMAGE:-ubuntu:24.04}


#################################################
# resolve gitea act runner version (latest stable release)
#################################################
gitea_runner_effective_version=$(curl -sSf 'https://gitea.com/api/v1/repos/gitea/runner/releases?draft=false&pre-release=false&limit=1' | jq -r '.[0].tag_name | ltrimstr("v")')


#################################################
# define tags
#################################################
declare -a tags=()
if [[ -n ${IMAGE_TAG:-} ]]; then
  tags+=("$IMAGE_TAG")
else
  tags+=("${DOCKER_IMAGE_TAG_PREFIX:-}$gitea_runner_effective_version")
fi


#################################################
# prepare docker
#################################################
run_step -- docker version


#################################################
# build the image
#################################################
image_name=$image_repo:${tags[0]}

build_opts=(
  --file "image/Dockerfile"
  --progress=plain
  --pull
  --build-arg BASE_IMAGE="$base_image"
  --build-arg GITEA_RUNNER_VERSION="$gitea_runner_effective_version"
)

if [[ $OSTYPE == "cygwin" || $OSTYPE == "msys" ]]; then
  project_root=$(cygpath -w "$project_root")
fi

run_step "Building docker image [$image_name]..." -- \
  docker build "${build_opts[@]}" -t "$image_name" "$project_root"


#################################################
# test image
#################################################
run_step "Testing docker image [$image_name]" -- \
  docker run --pull=never --rm "$image_name" gitea-runner --version

run_step "Listing docker images" -- docker images


#################################################
# push image
#################################################
if [[ ${DOCKER_PUSH_GHCR:-} == "true" ]]; then
  push_to_registry "ghcr.io/$image_repo"
fi
if [[ ${DOCKER_PUSH_SWR:-} == "true" ]]; then
  swr_registry=${DOCKER_SWR_REGISTRY:-swr.cn-southwest-2.myhuaweicloud.com}
  swr_namespace=${DOCKER_SWR_NAMESPACE:-gsc-hub}
  swr_image_name="${image_repo##*/}"
  push_to_registry "$swr_registry/$swr_namespace/$swr_image_name"
fi
