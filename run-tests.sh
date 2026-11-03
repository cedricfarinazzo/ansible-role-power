#!/usr/bin/env bash
# Script to run molecule tests for the power Ansible role

# Function to display usage
function show_usage() {
    echo "Usage: $0 [DISTRO]"
    echo
    echo "Run molecule tests for the power Ansible role"
    echo
    echo "Arguments:"
    echo "  DISTRO    Distribution to test with (default: debian13)"
    echo "            Supported: debian12, debian13, ubuntu2404, ubuntu2604"
    echo
    echo "Examples:"
    echo "  $0              # Test with Debian 13"
    echo "  $0 ubuntu2404   # Test with Ubuntu 24.04"
    echo
}

# Show help if requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

# Exit on any error
set -e

# Define colors for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Virtual environment path
VENV_PATH=".venv"

# Check for Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed. Docker is required for molecule tests.${NC}"
    echo "Please install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo -e "${RED}Docker is not running. Please start Docker daemon.${NC}"
    exit 1
fi

# Create the virtual environment once; install the pinned tooling every run so a pin bump lands
if [ ! -d "${VENV_PATH}" ]; then
    python3 -m venv "${VENV_PATH}"
fi
if ! "${VENV_PATH}/bin/pip" install --quiet -r requirements-dev.txt; then
    echo -e "${RED}Failed to install the tooling from requirements-dev.txt.${NC}"
    exit 1
fi
if ! "${VENV_PATH}/bin/ansible-galaxy" collection install -r requirements.yml; then
    echo -e "${RED}Failed to install Ansible collections.${NC}"
    exit 1
fi

# Display test information
echo -e "${GREEN}=== Power Role Test ===${NC}"
echo "Python virtual environment: ${VENV_PATH}"

# Pull Docker image in advance to avoid timeout issues
echo -e "${YELLOW}Pulling Docker image...${NC}"
docker pull geerlingguy/docker-${1:-debian13}-ansible:latest

# Set up environment variables
export MOLECULE_DISTRO=${1:-debian13}
export MOLECULE_NO_LOG=false
export MOLECULE_ROLE_NAME_CHECK=0

echo -e "${YELLOW}Running molecule test with ${MOLECULE_DISTRO}...${NC}"

# shellcheck source=/dev/null
source "${VENV_PATH}/bin/activate"
if molecule test; then
    echo -e "${GREEN}Tests completed successfully!${NC}"
else
    echo -e "${RED}Tests failed.${NC}"
    exit 1
fi
