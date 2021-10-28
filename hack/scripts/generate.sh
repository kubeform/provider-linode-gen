#!/bin/bash

# Copyright AppsCode Inc. and Contributors
#
# Licensed under the AppsCode Community License 1.0.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://github.com/appscode/licenses/raw/1.0.0/AppsCode-Community-1.0.0.md
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eou pipefail

SCRIPT_ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
pushd "$SCRIPT_ROOT"

# http://redsymbol.net/articles/bash-exit-traps/
function cleanup() {
    popd
}
trap cleanup EXIT

repo_uptodate() {
    # gomodfiles=(go.mod go.sum vendor/modules.txt)
    gomodfiles=(go.sum vendor/modules.txt)
    IFS=$'\n' read -r -d '' -a changed < <((git status -s | cut -d" " -f3) && printf '\0')
    changed+=("${gomodfiles[@]}")
    # https://stackoverflow.com/a/28161520
    IFS=$'\n' read -r -d '' -a diff < <((echo "${changed[@]}" "${gomodfiles[@]}" | tr ' ' '\n' | sort | uniq -u) && printf '\0')
    return ${#diff[@]}
}

gen_version=$(git rev-parse --short HEAD)

provider_name=linode
provider_repo="github.com/linode/terraform-provider-$provider_name"
provider_version=$(go mod edit -json | jq -r ".Require[] | select(.Path == \"${provider_repo}\") | .Version")
echo "$provider_version"

api_repo="github.com/kubeform/provider-${provider_name}-api"
controller_repo="github.com/kubeform/provider-${provider_name}-controller"
installer_repo="github.com/kubeform/installer"
# doc_repo ?

echo "installing generator"

go install -v ./...
generator="provider-${provider_name}-gen"
sudo mv "$(go env GOPATH)/bin/${generator}" /usr/local/bin
which $generator

echo "Checking if ${api_repo} needs to be updated ..."

tmp_dir=$(mktemp -d -t ${provider_name}-XXXXXXXXXX)
# always cleanup temp dir
# ref: https://opensource.com/article/20/6/bash-trap
trap \
    "{ rm -rf ""${tmp_dir}""; }" \
    SIGINT SIGTERM ERR EXIT

mkdir -p "${tmp_dir}"
pushd "$tmp_dir"
git clone --no-tags --no-recurse-submodules --depth=1 "https://${api_repo}.git"
repo_dir="provider-${provider_name}-api"
cd "$repo_dir" || exit
git checkout -b "gen-${provider_version}-${gen_version}"
rm -rf api apis client crds/*.yaml
mkdir -p api apis client
make gen-apis
go mod edit \
    -require=sigs.k8s.io/controller-runtime@v0.9.0 \
    -require=kmodules.xyz/client-go@5e9cebbf1dfa80943ecb52b43686b48ba5df8363 \
    -require=kubeform.dev/apimachinery@ba5604d5a1ccd6ea2c07c6457c8b03f11ab00f63
go mod tidy
go mod vendor
make gen fmt
go mod tidy
go mod vendor
git add --all
if repo_uptodate; then
    echo "Repository $api_repo is up-to-date."
else
    git commit -a -s -m "Generate code for provider@${provider_version} gen@${gen_version}"
    git push origin HEAD -f
    hub pull-request -f \
        --labels automerge \
        --message "Generate code for provider@${provider_version} gen@${gen_version}" \
        --message "$(git show -s --format=%b)"
fi
api_version=$(git rev-parse --short HEAD)

sleep 10 # don't cross GitHub rate limits

echo "Checking if ${controller_repo} needs to be updated ..."

cd "$tmp_dir" || exit
git clone --no-tags --no-recurse-submodules --depth=1 "https://${controller_repo}.git"
repo_dir="provider-${provider_name}-controller"
cd "$repo_dir" || exit
git checkout -b "gen-${provider_version}-${gen_version}"
rm -rf controllers
mkdir controllers
make gen-controllers

go mod edit \
    -replace=google.golang.org/api=google.golang.org/api@v0.59.0 \
    -require="${provider_repo}@${provider_version}" \
    -require="kubeform.dev/provider-${provider_name}-api@${api_version}" \
    -require=gomodules.xyz/logs@v0.0.3 \
    -require=sigs.k8s.io/controller-runtime@v0.9.0 \
    -require=kmodules.xyz/client-go@5e9cebbf1dfa80943ecb52b43686b48ba5df8363 \
    -require=kubeform.dev/apimachinery@ba5604d5a1ccd6ea2c07c6457c8b03f11ab00f63
go mod tidy
go mod vendor
make gen fmt
go mod tidy
go mod vendor
git add --all
if repo_uptodate; then
    echo "Repository $controller_repo is up-to-date."
else
    git commit -a -s -m "Generate code for provider@${provider_version} gen@${gen_version}"
    git push origin HEAD -f
    hub pull-request -f \
        --labels automerge \
        --message "Generate code for provider@${provider_version} gen@${gen_version}" \
        --message "$(git show -s --format=%b)"
fi
make qa

sleep 10 # don't cross GitHub rate limits

echo "Checking if ${installer_repo} needs to be updated ..."

cd "$tmp_dir" || exit
git clone --no-tags --no-recurse-submodules --depth=1 "https://${installer_repo}.git"
repo_dir=installer
cd "$repo_dir" || exit
git checkout -b "gen-${provider_version}-${gen_version}"
go run ./hack/generate/... --provider=${provider_name} --input-dir="${tmp_dir}"
# update provider tag?
make fmt
go mod tidy
go mod vendor
make gen fmt
go mod tidy
go mod vendor
git add --all
if repo_uptodate; then
    echo "Repository $installer_repo is up-to-date."
else
    git commit -a -s -m "Update ${provider_name} installer for provider@${provider_version} gen@${gen_version}"
    git push origin HEAD -f
    hub pull-request -f \
        --labels automerge \
        --message "Update ${provider_name} installer for provider@${provider_version} gen@${gen_version}" \
        --message "$(git show -s --format=%b)"
fi

# update docs repo?

popd
