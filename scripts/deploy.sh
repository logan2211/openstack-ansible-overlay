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

DEPLOY_HOST=${DEPLOY_HOST:-true}
DEPLOY_INFRASTRUCTURE=${DEPLOY_INFRASTRUCTURE:-true}
DEPLOY_CEPH=${DEPLOY_CEPH:-true}
DEPLOY_OPENSTACK=${DEPLOY_OPENSTACK:-true}
DEPLOY_SWIFT=${DEPLOY_SWIFT:-true}
DEPLOY_CEILOMETER=${DEPLOY_CEILOMETER:-true}
DEPLOY_TEMPEST=${DEPLOY_TEMPEST:-true}
COMMAND_LOGS=${COMMAND_LOGS:-"/openstack/log/ansible_cmd_logs/"}

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

  #look at converting this to the bootstrap-host role later.
  if [[ -f ${OVERLAY_DIR}/bootstrap_host_overrides.yml ]]; then
    export BOOTSTRAP_OPTS="@${OVERLAY_DIR}/bootstrap_host_overrides.yml"
  fi
  scripts/bootstrap-aio.sh

  if [[ "${DEPLOY_CEPH}" = true ]]; then
    pushd ${OVERLAY_DIR}/../tests
      BOOTSTRAP_OPTS=${BOOTSTRAP_OPTS:-''}
      ansible-playbook -i test-inventory.ini \
                       -e "${BOOTSTRAP_OPTS}" \
                       bootstrap-aio-ceph.yml
    popd
  fi
fi

if [[ "${UPDATE_DEPLOY_CONFIG}" = true ]]; then
  run_overrides

  scripts/pw-token-gen.py --file /etc/openstack_deploy/user_secrets.yml
fi

if [[ "${DEPLOY_OA}" = true ]]; then

  pushd ${OA_DIR}/playbooks
    if [ "${DEPLOY_HOST}" = true ]; then
      # Install all host bits
      run_ansible openstack-hosts-setup.yml
      run_ansible lxc-hosts-setup.yml

      # Apply security hardening
      # NOTE(mattt): We have to skip V-38462 as openstack-infra are now building
      #              images with apt config Apt::Get::AllowUnauthenticated set
      #              to true.
      run_ansible --skip-tag V-38462 security-hardening.yml

      # Bring the lxc bridge down and back up to ensures the iptables rules are in-place
      # This also will ensure that the lxc dnsmasq rules are active.
      mkdir -p "${COMMAND_LOGS}/host_net_bounce"
      ansible hosts -m shell \
                    -a '(ifdown lxcbr0 || true); ifup lxcbr0' \
                    -t "${COMMAND_LOGS}/host_net_bounce" \
                    &> ${COMMAND_LOGS}/host_net_bounce.log

      # Create the containers.
      run_ansible lxc-containers-create.yml
    fi

    if [ "${DEPLOY_INFRASTRUCTURE}" = true ]; then
      # Install all of the infra bits
      run_ansible repo-install.yml
      run_ansible haproxy-install.yml
      run_ansible memcached-install.yml

      mkdir -p "${COMMAND_LOGS}/repo_data"
      ansible 'repo_all[0]' -m raw \
                            -a 'find  /var/www/repo/os-releases -type l' \
                            -t "${COMMAND_LOGS}/repo_data"

      run_ansible galera-install.yml
      run_ansible rabbitmq-install.yml

      if [ "${DEPLOY_CEPH}" = true ]; then
        pushd ${OVERLAY_DIR}/playbooks
          run_ansible ceph-install.yml
        popd
      fi

      run_ansible utility-install.yml
      run_ansible rsyslog-install.yml
    fi

    if [ "${DEPLOY_OPENSTACK}" = true ]; then
      # install all of the compute Bits
      run_ansible os-keystone-install.yml
      run_ansible os-glance-install.yml
      run_ansible os-cinder-install.yml
      run_ansible os-nova-install.yml
      run_ansible os-neutron-install.yml
      run_ansible os-heat-install.yml
      run_ansible os-horizon-install.yml
    fi

    # If ceilometer is deployed, it must be run before
    # swift, since the swift playbooks will make reference
    # to the ceilometer user when applying the reselleradmin
    # role
    if [ "${DEPLOY_CEILOMETER}" = true ]; then
      run_ansible os-ceilometer-install.yml
      run_ansible os-aodh-install.yml
    fi

    if [ "${DEPLOY_SWIFT}" = true ]; then
      if [ "${DEPLOY_OPENSTACK}" = false ]; then
        # When os install is no, make sure we still have keystone for use in swift.
        run_ansible os-keystone-install.yml
      fi
      # install all of the swift Bits
      run_ansible os-swift-install.yml
    fi

    if [ "${DEPLOY_TEMPEST}" = true ]; then
      # Deploy tempest
      run_ansible os-tempest-install.yml
    fi

  popd

  pushd ${OVERLAY_DIR}/playbooks
    run_ansible ntp-install.yml
  popd
fi
