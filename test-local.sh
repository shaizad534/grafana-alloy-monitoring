#!/bin/bash
# =============================================================================
# Local Test Script for Alloy Agent Deployment (Install Only)
# =============================================================================
# This script allows you to test the playbook locally with local packages
# Usage: ./test-local.sh [version] [environment]
# Example: ./test-local.sh 1.19.2 dev
# =============================================================================

set -euo pipefail

# Default values
ALLOY_VERSION="${1:-1.19.2}"
ENVIRONMENT="${2:-dev}"
ARTIFACTORY_URL="${ARTIFACTORY_URL:-https://your-artifactory.example.com/artifactory/grafana-alloy}"
PACKAGES_DIR="${PACKAGES_DIR:-packages}"
ANSIBLE_INVENTORY="ansible/inventory/${ENVIRONMENT}/hosts.yml"
PLAYBOOK="ansible/playbooks/deploy_alloy.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running from correct directory
if [[ ! -f "ansible/ansible.cfg" ]]; then
    log_error "Please run this script from the grafana-alloy-monitoring root directory"
    exit 1
fi

log_info "Starting local test deployment"
log_info "Alloy Version: ${ALLOY_VERSION}"
log_info "Environment: ${ENVIRONMENT}"
log_info "Artifactory URL: ${ARTIFACTORY_URL}"
log_info "Packages Directory: ${PACKAGES_DIR}"

# Check if ansible is installed
if ! command -v ansible-playbook &> /dev/null; then
    log_error "ansible-playbook not found. Please install Ansible."
    exit 1
fi

# Check if ansible-lint is installed
if ! command -v ansible-lint &> /dev/null; then
    log_warning "ansible-lint not found. Installing..."
    pip3 install --quiet ansible-lint
fi

# Check for local packages
DEB_PACKAGE="${PACKAGES_DIR}/alloy-${ALLOY_VERSION}-1.amd64.deb"
RPM_PACKAGE="${PACKAGES_DIR}/alloy-${ALLOY_VERSION}-1.amd64.rpm"
WIN_PACKAGE="${PACKAGES_DIR}/alloy-installer-windows-amd64.exe.zip"

log_info "Checking for local packages..."
MISSING_PACKAGES=0

if [[ ! -f "${DEB_PACKAGE}" ]]; then
    log_warning "Missing Debian package: ${DEB_PACKAGE}"
    MISSING_PACKAGES=1
else
    log_success "Found Debian package: ${DEB_PACKAGE}"
fi

if [[ ! -f "${RPM_PACKAGE}" ]]; then
    log_warning "Missing RPM package: ${RPM_PACKAGE}"
    MISSING_PACKAGES=1
else
    log_success "Found RPM package: ${RPM_PACKAGE}"
fi

if [[ ! -f "${WIN_PACKAGE}" ]]; then
    log_warning "Missing Windows package: ${WIN_PACKAGE}"
    MISSING_PACKAGES=1
else
    log_success "Found Windows package: ${WIN_PACKAGE}"
fi

if [[ ${MISSING_PACKAGES} -eq 1 ]]; then
    log_warning "Some packages are missing. The playbook will attempt to download from Artifactory."
    log_info "To use local packages, place them in: ${PACKAGES_DIR}/"
fi

# Install required collections
log_info "Installing required Ansible collections..."
cd ansible
ansible-galaxy collection install -r requirements.yml
cd ..

# Run ansible-lint
log_info "Running ansible-lint..."
cd ansible
ansible-lint playbooks/deploy_alloy.yml -r roles/
cd ..

# Syntax check
log_info "Running syntax check..."
cd ansible
ansible-playbook --syntax-check -i "inventory/${ENVIRONMENT}/hosts.yml" playbooks/deploy_alloy.yml \
    -e "alloy_version=${ALLOY_VERSION} alloy_download_base_url=${ARTIFACTORY_URL} alloy_package_local_dir=../${PACKAGES_DIR}"
cd ..

# Run the playbook
log_info "Running playbook (DRY RUN first)..."
cd ansible
ansible-playbook -i "inventory/${ENVIRONMENT}/hosts.yml" playbooks/deploy_alloy.yml \
    -e "alloy_version=${ALLOY_VERSION} alloy_download_base_url=${ARTIFACTORY_URL} alloy_package_local_dir=../${PACKAGES_DIR}" \
    --check --diff
cd ..

# Ask for confirmation before actual run
read -p "Dry run completed. Proceed with actual deployment? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Deployment cancelled by user."
    exit 0
fi

log_info "Running actual deployment..."
cd ansible
ansible-playbook -i "inventory/${ENVIRONMENT}/hosts.yml" playbooks/deploy_alloy.yml \
    -e "alloy_version=${ALLOY_VERSION} alloy_download_base_url=${ARTIFACTORY_URL} alloy_package_local_dir=../${PACKAGES_DIR}"
cd ..

log_success "Deployment completed successfully!"

# Verify deployment
log_info "Verifying deployment..."
for host in $(cd ansible && ansible-inventory -i "inventory/${ENVIRONMENT}/hosts.yml" --list | jq -r '.all.hosts[]' 2>/dev/null); do
    log_info "Checking ${host}..."
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${host}" "curl -s http://localhost:12345/-/ready" 2>/dev/null | grep -q "ready"; then
        log_success "${host}: Alloy is RUNNING"
    else
        log_warning "${host}: Alloy not responding on port 12345"
    fi
done

log_success "All done!"