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

export MAX_RETRIES=${MAX_RETRIES:-"2"}
export TESTR_OPTS=${TESTR_OPTS:-''}
export PYTHONUNBUFFERED=1
export ANSIBLE_ROLE_FETCH_MODE="git-clone"

#options for deploy script
export UPDATE_ANSIBLE=true
export DEPLOY_AIO=true
export DEPLOY_OA=true
export DEPLOY_CEPH=true
export DEPLOY_TEMPEST=true

$(dirname ${0})/deploy.sh
