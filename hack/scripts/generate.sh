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

set -xeou pipefail

SCRIPT_ROOT=$(realpath $(dirname "${BASH_SOURCE[0]}")/../..)
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
pushd $SCRIPT_ROOT

# http://redsymbol.net/articles/bash-exit-traps/
function cleanup() {
    popd
}
trap cleanup EXIT

repo_uptodate() {
    # gomodfiles=(go.mod go.sum vendor/modules.txt)
    gomodfiles=(go.sum vendor/modules.txt)
    changed=($(git diff --name-only))
    changed+=("${gomodfiles[@]}")
    # https://stackoverflow.com/a/28161520
    diff=($(echo ${changed[@]} ${gomodfiles[@]} | tr ' ' '\n' | sort | uniq -u))
    return ${#diff[@]}
}

gen_version=$(git rev-parse --short HEAD)

provider_name=linode
provider_repo="github.com/linode/terraform-provider-$provider_name"
provider_version=$(go mod edit -json | jq -r ".Require[] | select(.Path == \"${provider_repo}\") | .Version")
echo $provider_version

api_repo="github.com/kubeform/provider-${provider_name}-api"
controller_repo="github.com/kubeform/provider-${provider_name}-controller"
installer_repo="github.com/kubeform/installer"
# doc_repo ?

echo "installing generator"

go install -v ./...
generator="provider-${provider_name}-gen"
sudo mv $(go env GOPATH)/bin/${generator} /usr/local/bin
which $generator

echo "Checking if ${api_repo} needs to be updated ..."

tmp_dir=$(mktemp -d -t ${provider_name}-XXXXXXXXXX)
# always cleanup temp dir
# ref: https://opensource.com/article/20/6/bash-trap
trap \
    "{ rm -rf "${tmp_dir}"; }" \
    SIGINT SIGTERM ERR EXIT

mkdir -p ${tmp_dir}
pushd $tmp_dir
git clone --no-tags --no-recurse-submodules --depth=1 "https://${api_repo}.git"
repo_dir=$(ls -b1)
cd $repo_dir
git checkout -b "gen/${provider_version}-${gen_version}"
make gen-apis
go mod edit \
    -require=sigs.k8s.io/controller-runtime@v0.9.0 \
    -require=kmodules.xyz/client-go@13d22e91512b80f1ac6cbb4452c3be73e7a21b88 \
    -require=kubeform.dev/apimachinery@1265434c1a63a970f3a16f0ad4e3171f130b6f11
go mod tidy
go mod vendor
make gen fmt
if repo_uptodate; then
    echo "Repository $api_repo is up-to-date."
    exit 0
else
    git commit -a -s -m "Generate code for provider:${provider_version} gen:${gen_version}"
    git push -u origin HEAD
    # hub pull-request \
    #     --labels automerge \
    #     --message "Generate code for provider:${provider_version} gen:${gen_version}" \
    #     --message "$(git show -s --format=%b)"
    api_version=$(git rev-parse --short HEAD)
fi
cd ..

sleep 10 # don't cross GitHub rate limits

echo "Checking if ${controller_repo} needs to be updated ..."

cd $tmp_dir
git clone --no-tags --no-recurse-submodules --depth=1 "https://${controller_repo}.git"
repo_dir=$(ls -b1)
cd $repo_dir
git checkout -b "gen/${provider_version}-${gen_version}"
make controller-gen
go mod edit \
    -require="${provider_repo}@${provider_version}" \
    -require="${api_repo}@${api_version}" \
    -require=sigs.k8s.io/controller-runtime@v0.9.0 \
    -require=kmodules.xyz/client-go@13d22e91512b80f1ac6cbb4452c3be73e7a21b88 \
    -require=kubeform.dev/apimachinery@1265434c1a63a970f3a16f0ad4e3171f130b6f11
go mod tidy
go mod vendor
make gen fmt
if repo_uptodate; then
    echo "Repository $controller_repo is up-to-date."
    exit 0
else
    git commit -a -s -m "Generate code for provider:${provider_version} gen:${gen_version}"
    git push -u origin HEAD
    # hub pull-request \
    #     --labels automerge \
    #     --message "Generate code for provider:${provider_version} gen:${gen_version}" \
    #     --message "$(git show -s --format=%b)"
    make qa
fi
cd ..

sleep 10 # don't cross GitHub rate limits

echo "Checking if ${installer_repo} needs to be updated ..."

cd $tmp_dir
git clone --no-tags --no-recurse-submodules --depth=1 "https://${installer_repo}.git"
repo_dir=$(ls -b1)
cd $repo_dir
git checkout -b "gen/${provider_version}-${gen_version}"
go run ./hack/generate/... --provider=${provider_name} --input-dir=${tmp_dir}
# update provider tag?
go mod tidy
go mod vendor
make gen fmt
if repo_uptodate; then
    echo "Repository $installer_repo is up-to-date."
    exit 0
else
    git commit -a -s -m "Generate code for provider:${provider_version} gen:${gen_version}"
    git push -u origin HEAD
    # hub pull-request \
    #     --labels automerge \
    #     --message "Generate code for provider:${provider_version} gen:${gen_version}" \
    #     --message "$(git show -s --format=%b)"
fi
cd ..

popd
