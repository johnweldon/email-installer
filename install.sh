#!/bin/bash

set -euo pipefail

# Ensure non-interactive mode for all package installations
export DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-${SCRIPT_DIR}/config.yaml}"
LOG_FILE="/var/log/email-installer.log"
DATA_DIR=""
REPORT_FILE=""

source "${SCRIPT_DIR}/lib/functions.sh"
source "${SCRIPT_DIR}/lib/postfix.sh"
source "${SCRIPT_DIR}/lib/dovecot.sh"
source "${SCRIPT_DIR}/lib/dns.sh"
source "${SCRIPT_DIR}/lib/certificates.sh"
source "${SCRIPT_DIR}/lib/services.sh"
source "${SCRIPT_DIR}/lib/backup.sh"

main() {
  echo "Email Server Installer - Starting installation..."
  echo "Using configuration: ${CONFIG_FILE}"

  # Check if running as root
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
  fi

  # Check OS compatibility
  check_os_compatibility

  # Install essential packages first (python3, jq needed for config parsing)
  install_essential_packages

  # Configure all packages for non-interactive installation
  configure_noninteractive_packages

  # Parse configuration
  parse_configuration "${CONFIG_FILE}"

  # Validate configuration
  validate_configuration

  # Create data directories
  setup_data_directories

  # Install email server packages
  install_email_packages

  # Configure certificates
  setup_certificates

  # Configure Postfix (SMTP)
  configure_postfix

  # Configure Dovecot (IMAP/POP3)
  configure_dovecot

  # Setup users and domains
  setup_users_and_domains

  # Generate DNS records report
  generate_dns_report

  # Generate service status report
  generate_service_report

  # Setup automatic backups
  schedule_automatic_backups

  # Start services
  start_services

  # Perform initial backup
  backup_email_server

  echo "Installation completed successfully!"
  echo "DNS records report: ${REPORT_FILE}"
  echo "Service status report: ${REPORT_FILE%.dns}.services"
}

check_os_compatibility() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
  else
    echo "Cannot determine OS version"
    exit 1
  fi

  case $OS in
  ubuntu | debian)
    PKG_MANAGER="apt-get"
    ;;
  centos | rhel | fedora)
    PKG_MANAGER="yum"
    ;;
  *)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
  esac
}

install_essential_packages() {
  echo "Installing essential packages for configuration parsing..."

  case $PKG_MANAGER in
  apt-get)
    apt-get update
    apt-get install -y \
      python3 \
      python3-yaml \
      jq \
      openssl \
      debconf-utils
    ;;
  yum)
    yum install -y epel-release
    yum install -y \
      python3 \
      python3-pyyaml \
      jq \
      openssl
    ;;
  esac
}

configure_noninteractive_packages() {
  echo "Pre-configuring packages for non-interactive installation..."

  case $PKG_MANAGER in
  apt-get)
    # Pre-configure Postfix to prevent interactive prompts
    echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
    echo "postfix postfix/mailname string ${HOSTNAME}" | debconf-set-selections
    echo "postfix postfix/destinations string ${HOSTNAME}, localhost" | debconf-set-selections
    echo "postfix postfix/chattr boolean false" | debconf-set-selections
    echo "postfix postfix/mailbox_limit string 0" | debconf-set-selections
    echo "postfix postfix/recipient_delim string +" | debconf-set-selections
    echo "postfix postfix/mynetworks string 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128" | debconf-set-selections
    echo "postfix postfix/protocols select all" | debconf-set-selections
    echo "postfix postfix/relayhost string" | debconf-set-selections
    echo "postfix postfix/root_address string" | debconf-set-selections

    # Pre-configure Dovecot
    echo "dovecot-core dovecot-core/create-ssl-cert boolean true" | debconf-set-selections
    echo "dovecot-core dovecot-core/ssl-cert-name string dovecot" | debconf-set-selections

    # Pre-configure other packages
    echo "ssl-cert make-ssl-cert/hostname string ${HOSTNAME}" | debconf-set-selections
    echo "ssl-cert make-ssl-cert/country string US" | debconf-set-selections

    # Disable services from starting during installation
    echo '#!/bin/sh' >/usr/sbin/policy-rc.d
    echo 'exit 101' >>/usr/sbin/policy-rc.d
    chmod +x /usr/sbin/policy-rc.d

    echo "Packages pre-configured for automated installation"
    ;;
  yum)
    # No specific configuration needed for yum-based systems
    :
    ;;
  esac
}

install_email_packages() {
  echo "Installing email server packages..."

  case $PKG_MANAGER in
  apt-get)
    # Install email packages (debconf already configured)
    apt-get install -y \
      postfix \
      postfix-mysql \
      dovecot-core \
      dovecot-imapd \
      dovecot-pop3d \
      dovecot-lmtpd \
      dovecot-mysql \
      certbot \
      cron \
      iproute2

    # Re-enable service starting after installation
    rm -f /usr/sbin/policy-rc.d
    ;;
  yum)
    yum install -y \
      postfix \
      dovecot \
      dovecot-mysql \
      certbot
    ;;
  esac
}

start_services() {
  echo "Starting email services..."

  systemctl restart postfix
  systemctl enable postfix

  systemctl restart dovecot
  systemctl enable dovecot

  echo "Services started successfully"
}

# Trap errors and cleanup
trap 'echo "Error occurred at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"

