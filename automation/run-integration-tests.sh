#!/bin/sh -ex

EXEC_PATH=$(dirname "$(realpath "$0")")
PROJECT_PATH="$(dirname $EXEC_PATH)"
DOCKER_IMAGE="nmstate/centos7-nmstate-dev"

NET0="nmstate-net0"
NET1="nmstate-net1"

test -t 1 && USE_TTY="-t"

function remove_container {
    res=$?
    [ "$res" -ne 0 ] && echo "*** ERROR: $res"
    docker stop $CONTAINER_ID
    docker rm $CONTAINER_ID
    docker network rm $NET0
    docker network rm $NET1
}

function pyclean {
        find . -type f -name "*.py[co]" -delete
        find . -type d -name "__pycache__" -delete
}

function docker_exec {
    docker exec $USE_TTY -i $CONTAINER_ID /bin/bash -c "$1"
}

function add_extra_networks {
    docker network create $NET0 || true
    docker network create $NET1 || true
    docker network connect $NET0 $CONTAINER_ID
    docker network connect $NET1 $CONTAINER_ID
    docker_exec '
      ip addr flush eth1 && \
      ip addr flush eth2
    '
}

function dump_network_info {
    docker_exec '
      nmcli dev; \
      nmcli con; \
      ip addr; \
      ip route; \
      cat /etc/resolv.conf; \
      ping -c 1 github.com || true
    '
}

function install_nmstate {
    docker_exec '
      cd /workspace/nmstate &&
      pip install .
    '
}

function run_tests {
    docker_exec '
      cd /workspace/nmstate &&
      pytest \
        --log-level=DEBUG \
        --durations=5 \
        --cov=libnmstate \
        --cov=nmstatectl \
        --cov-report=html:htmlcov-py27 \
        tests/integration
    '
}

cd $EXEC_PATH 
docker --version && cat /etc/resolv.conf && ping -c 1 github.com

CONTAINER_ID="$(docker run --privileged -d -v /sys/fs/cgroup:/sys/fs/cgroup:ro -v $PROJECT_PATH:/workspace/nmstate $DOCKER_IMAGE)"
trap remove_container EXIT
docker_exec 'systemctl start dbus.socket'
pyclean

dump_network_info
install_nmstate
add_extra_networks
dump_network_info
run_tests