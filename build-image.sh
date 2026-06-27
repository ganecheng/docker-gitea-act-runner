#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com)
# SPDX-FileContributor: Sebastian Thomschke
# SPDX-License-Identifier: Apache-2.0
# SPDX-ArtifactOfProjectHomePage: https://github.com/vegardit/docker-gitea-act-runner

set -euo pipefail


#################################################
# helper functions
#################################################
function push_to_registry() {
  local target="$1:$IMAGE_TAG"
  docker images
  docker history "$image_name"
  echo "Tagging [$image_name] -> [$target]"
  docker tag "$image_name" "$target"
  echo "Pushing [$target]"
  docker push "$target"
}


#################################################
# resolve gitea act runner version (latest stable release)
#################################################
gitea_runner_effective_version=$(curl -sSf 'https://gitea.com/api/v1/repos/gitea/runner/releases?draft=false&pre-release=false&limit=1' | jq -r '.[0].tag_name | ltrimstr("v")')


#################################################
# build the image
#################################################
image_name=$DOCKER_IMAGE_REPO:$IMAGE_TAG

build_opts=(
  --file "image/Dockerfile"
  --progress=plain
  --pull
  --build-arg BASE_IMAGE="$DOCKER_BASE_IMAGE"
  --build-arg GITEA_RUNNER_VERSION="$gitea_runner_effective_version"
)

echo "Building docker image [$image_name]..."
docker build "${build_opts[@]}" -t "$image_name" .


#################################################
# test image
#################################################
echo "Testing docker image [$image_name]..."
docker run --pull=never --rm "$image_name" gitea-runner --version

echo "Listing docker images..."
docker images


#################################################
# push image
#################################################
if [[ ${DOCKER_PUSH_GHCR:-} == "true" ]]; then
  push_to_registry "ghcr.io/$DOCKER_IMAGE_REPO"
fi
if [[ ${DOCKER_PUSH_SWR:-} == "true" ]]; then
  swr_registry=${DOCKER_SWR_REGISTRY:-swr.cn-southwest-2.myhuaweicloud.com}
  swr_namespace=${DOCKER_SWR_NAMESPACE:-gsc-hub}
  swr_image_name="${DOCKER_IMAGE_REPO##*/}"
  push_to_registry "$swr_registry/$swr_namespace/$swr_image_name"
fi
