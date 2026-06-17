#!/bin/bash

isEverythinkOk=1

# container runtime - either docker or podman, prefer podman
if command -v podman &>/dev/null;
then
    version=$(podman --version | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)
    echo "Podman $version found"
elif command -v docker &>/dev/null;
then
    version=$(docker --version | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)
    echo "Docker $version found"
else
    echo "Container runtime not found (Docker or Podman)"
    echo "Install Podman: https://podman.io/docs/installation"
    echo "Install Docker: https://docs.docker.com/engine/install/"
    isEverythinkOk=0
fi

# ansible 2.14+
needVersion=2.14
if command -v ansible-playbook &>/dev/null;
then
    currentVersion=$(ansible-playbook --version | head -n 1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)
    if [ "$(printf '%s\n' "$needVersion" "$currentVersion" | sort -V | head -n 1)" = "$needVersion" ];
    then
        echo "Ansible $currentVersion found"
    else
        echo "Ansible $currentVersion found but version must be 2.14+"
        echo "Install: pip install ansible (or use your OS package manager)"
        isEverythinkOk=0
    fi
else
    echo "Ansible not found"
    echo "Install: pip install ansible (or use your OS package manager)"
    isEverythinkOk=0
fi

if [ "$isEverythinkOk" -eq 1 ];
then
    echo "Proceeding..."
    exit 0
else
    echo "Please install the missing dependencies and retry."
    exit 1
fi
