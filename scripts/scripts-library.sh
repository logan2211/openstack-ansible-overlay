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

export UPDATE_ANSIBLE=${UPDATE_ANSIBLE:-false}
export UPDATE_DEPLOY_CONFIG=${UPDATE_DEPLOY_CONFIG:-true}
export DEPLOY_AIO=${DEPLOY_AIO:-false}
export DEPLOY_OA=${DEPLOY_OA:-false}
export FORKS=${FORKS:-$(grep -c ^processor /proc/cpuinfo)}
export ANSIBLE_PARAMETERS=${ANSIBLE_PARAMETERS:-""}
export BOOTSTRAP_OPTS=${BOOTSTRAP_OPTS:-""}

export OVERLAY_SCRIPT_PATH=$(dirname $(readlink -f "$0"))
export OA_DIR=$(readlink -f "$OVERLAY_SCRIPT_PATH"/../openstack-ansible)
export OVERLAY_DIR=$(readlink -f "$OVERLAY_SCRIPT_PATH"/../overlay)

#override the inventory directory defined in the OSA ansible.cfg
export ANSIBLE_INVENTORY="${OVERLAY_DIR}/playbooks/inventory"
export ANSIBLE_ROLES_PATH="/etc/ansible/roles:${OA_DIR}/playbooks/roles:${OVERLAY_DIR}/playbooks/roles"

function run_ansible {
  openstack-ansible ${ANSIBLE_PARAMETERS} --forks ${FORKS} $@
}

function sudo_run_ansible {
  sudo openstack-ansible ${ANSIBLE_PARAMETERS} --forks ${FORKS} $@
}

function run_overrides {
  #build the initial config directory if it does not exist
  if [[ ! -d /etc/openstack_deploy ]]; then
    pushd ${OA_DIR}
      cp -R etc/openstack_deploy /etc/openstack_deploy
    popd
  fi

  #newer versions of OSA do not prep the env.d override directory
  if [[ ! -d /etc/openstack_deploy/env.d ]]; then
    mkdir /etc/openstack_deploy/env.d
  fi

  if [[ "${DEPLOY_AIO}" = true ]]; then
    #the configuraiton merger will overwrite the user_variables file written by the bootstrap-aio role, so move it out of the way.
    mv /etc/openstack_deploy/user_variables.yml /etc/openstack_deploy/user_variables_aio.yml
  fi

  #there should be an openstack_deploy dir ready for *.yml overrides now.
  local VARS_FILES=$(find ${OA_DIR}/etc/openstack_deploy ${OVERLAY_DIR}/env/openstack_deploy ${OVERLAY_DIR}/local/openstack_deploy -maxdepth 1 -iname '*.yml' -printf '%P\n' | sort | uniq)
  for i in $VARS_FILES; do
    if [[ "${i}" == "user_secrets.yml" ]]; then
      continue
    fi
    ${OVERLAY_SCRIPT_PATH}/update-yaml.py "/etc/openstack_deploy/${i}" "${OA_DIR}/etc/openstack_deploy/${i}" "${OVERLAY_DIR}/env/openstack_deploy/${i}" "${OVERLAY_DIR}/local/openstack_deploy/${i}"
  done

  #build the env.d overrides. OSA automatically handles env.d merging with its
  #base environment, so we only need to handle our override layers without
  #considering the OSA base config.
  local ENV_FILES=$(find ${OVERLAY_DIR}/env/env.d ${OVERLAY_DIR}/local/env.d -maxdepth 1 -iname '*.yml' -printf '%P\n' | sort | uniq)
  for i in $ENV_FILES; do
    ${OVERLAY_SCRIPT_PATH}/update-yaml.py "/etc/openstack_deploy/env.d/${i}" "${OVERLAY_DIR}/env/env.d/${i}" "${OVERLAY_DIR}/local/env.d/${i}"
  done

  #build the group_vars overrides
  local GROUP_VARS_FILES=$(find ${OA_DIR}/playbooks/inventory/group_vars ${OVERLAY_DIR}/env/group_vars ${OVERLAY_DIR}/local/group_vars -maxdepth 1 -iname '*.yml' -printf '%P\n' | sort | uniq)
  for i in $GROUP_VARS_FILES; do
    ${OVERLAY_SCRIPT_PATH}/update-yaml.py "${OVERLAY_DIR}/playbooks/inventory/group_vars/${i}" "${OA_DIR}/playbooks/inventory/group_vars/${i}" "${OVERLAY_DIR}/env/group_vars/${i}" "${OVERLAY_DIR}/local/group_vars/${i}"
  done
}
