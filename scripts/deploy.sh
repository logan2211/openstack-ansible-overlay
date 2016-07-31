#!/usr/bin/env bash
# Copyright 2016, Logan Vig <logan2211@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e -u -x
set -o pipefail

. $(dirname $(readlink -f "$0"))/scripts-library.sh

#begin bootstrap
cd ${OA_DIR}

#bootstrap ansible if necessary
if [[ "$UPDATE_ANSIBLE" = true ]] || [[ ! $(which openstack-ansible) ]]; then
  ${OVERLAY_SCRIPT_PATH}/update-yaml.py -l "${OVERLAY_DIR}/../ansible-role-requirements.yml" "${OA_DIR}/ansible-role-requirements.yml" "${OVERLAY_DIR}/env/ansible-role-requirements.yml" "${OVERLAY_DIR}/local/ansible-role-requirements.yml"
  export ANSIBLE_ROLE_FETCH_MODE="git-clone"
  export ANSIBLE_ROLE_FILE="${OVERLAY_DIR}/../ansible-role-requirements.yml"
  scripts/bootstrap-ansible.sh
  sed -ri "s|^(export ANSIBLE_ROLES_PATH).*$|\1=\"\$\{ANSIBLE_ROLES_PATH:-${ANSIBLE_ROLES_PATH}\}\"|" /usr/local/bin/openstack-ansible.rc
  sed -ri "s|^(export ANSIBLE_INVENTORY).*$|\1=\"\$\{ANSIBLE_INVENTORY:-${ANSIBLE_INVENTORY}\}\"|" /usr/local/bin/openstack-ansible.rc
fi

# bootstrap the AIO
if [[ "${DEPLOY_AIO}" = true ]]; then
  # force the deployment of haproxy for an AIO
  export DEPLOY_LB="yes"

  #look at converting this to the bootstrap-host role later.
  if [[ -f ${OVERLAY_DIR}/bootstrap_host_overrides.yml ]]; then
    export BOOTSTRAP_OPTS="@${OVERLAY_DIR}/bootstrap_host_overrides.yml"
  fi
  scripts/bootstrap-aio.sh
fi

if [[ "$UPDATE_DEPLOY_CONFIG" == "yes" ]]; then
  run_overrides

  scripts/pw-token-gen.py --file /etc/openstack_deploy/user_secrets.yml
fi

if [[ "${DEPLOY_OA}" = true ]]; then
  scripts/run-playbooks.sh

  pushd ${OVERLAY_DIR}/playbooks
    run_ansible ntp-install.yml
  popd
fi
