#!/bin/bash

# Email Server Management Script
# Provides easy access to common management tasks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"

# Source library functions
source "${SCRIPT_DIR}/lib/functions.sh"
source "${SCRIPT_DIR}/lib/backup.sh"
source "${SCRIPT_DIR}/lib/services.sh"
source "${SCRIPT_DIR}/lib/dns.sh"

# Parse configuration if it exists
if [[ -f "$CONFIG_FILE" ]]; then
  parse_configuration "$CONFIG_FILE"
else
  # Try to detect existing installation and set defaults
  if [[ -d "/var/mail-server" ]]; then
    echo "Detected existing installation, using default paths..."
    DATA_DIR="/var/mail-server"
    DOMAINS_FILE="$DATA_DIR/domains.txt"
    USERS_FILE="$DATA_DIR/users.txt"
    CERTS_FILE="$DATA_DIR/certificates.txt"
    REPORT_FILE="$DATA_DIR/reports/dns-records-$(date +%Y%m%d-%H%M%S).txt"
    HOSTNAME=$(hostname -f 2>/dev/null || hostname)
  else
    echo "No configuration file found and no existing installation detected."
    echo "Please run the installer first or provide a config.yaml file."
    exit 1
  fi
fi

show_usage() {
  cat <<EOF
Email Server Management Tool

Usage: $0 <command> [options]

Commands:
    install [config.yaml]     - Install email server with configuration
    backup                    - Create backup of email server
    restore <backup_file>     - Restore from backup file
    status                    - Show service status
    health                    - Check service health
    dns-report                - Generate DNS records report
    test-email [email]        - Send test email
    add-user                  - Add new email user (interactive)
    list-users                - List all configured users
    queue                     - Show mail queue status
    logs [service]           - Show service logs (postfix/dovecot)
    restart [service]        - Restart services
    help                     - Show this help message

Examples:
    $0 install                      # Install with default config.yaml
    $0 install myconfig.yaml        # Install with custom config
    $0 backup                       # Create backup
    $0 restore backup-20240101.tar.gz
    $0 status                       # Show service status
    $0 test-email admin@example.com
    $0 logs postfix                 # Show postfix logs
    $0 restart                      # Restart all services

EOF
}

cmd_install() {
  local config="${1:-$CONFIG_FILE}"
  if [[ ! -f "$config" ]]; then
    echo "Error: Configuration file not found: $config"
    echo "Copy config.yaml.example to config.yaml and customize it"
    exit 1
  fi
  exec "${SCRIPT_DIR}/install.sh" "$config"
}

cmd_backup() {
  if [[ -z "$DATA_DIR" ]]; then
    echo "Error: Configuration not loaded. Run installer first."
    exit 1
  fi
  backup_email_server
}

cmd_restore() {
  local backup_file="$1"
  if [[ -z "$backup_file" ]]; then
    echo "Error: Backup file required"
    echo "Usage: $0 restore <backup_file>"
    exit 1
  fi
  restore_email_server "$backup_file"
}

cmd_status() {
  if [[ -z "$DATA_DIR" ]]; then
    echo "Error: Configuration not loaded. Run installer first."
    exit 1
  fi
  generate_service_report
  cat "${REPORT_FILE%.dns}.services"
}

cmd_health() {
  check_service_health
}

cmd_dns_report() {
  if [[ -z "$DATA_DIR" ]]; then
    echo "Error: Configuration not loaded. Run installer first."
    exit 1
  fi
  generate_dns_report
  cat "$REPORT_FILE"
}

cmd_test_email() {
  local email="${1:-}"
  test_email_delivery "$email"
}

cmd_add_user() {
  echo "Add New Email User"
  echo "-----------------"
  read -p "Domain: " domain
  read -p "Username: " username
  read -s -p "Password: " password
  echo

  local email="${username}@${domain}"

  # Add to virtual mailbox
  echo "$email $domain/$username/" >>/etc/postfix/virtual_mailbox
  postmap /etc/postfix/virtual_mailbox

  # Add to Dovecot users
  local password_hash=$(doveadm pw -s SHA512-CRYPT -p "$password")
  echo "$email:$password_hash" >>/etc/dovecot/users

  # Create mail directory
  mkdir -p "$DATA_DIR/mail/vhosts/$domain/$username/Maildir"
  mkdir -p "$DATA_DIR/mail/vhosts/$domain/$username/Maildir"/{cur,new,tmp}
  chown -R mail:mail "$DATA_DIR/mail/vhosts/$domain/$username"

  echo "User $email added successfully"

  # Reload services
  systemctl reload postfix dovecot
}

cmd_list_users() {
  echo "Configured Email Users:"
  echo "----------------------"
  if [[ -f /etc/dovecot/users ]]; then
    cut -d: -f1 /etc/dovecot/users | sort
  else
    echo "No users configured"
  fi
}

cmd_queue() {
  monitor_mail_queue
}

cmd_logs() {
  local service="${1:-all}"

  case $service in
  postfix)
    tail -f "$DATA_DIR/logs/postfix.log" 2>/dev/null ||
      journalctl -u postfix -f
    ;;
  dovecot)
    tail -f "$DATA_DIR/logs/dovecot.log" 2>/dev/null ||
      journalctl -u dovecot -f
    ;;
  all | *)
    echo "=== Recent Postfix Logs ==="
    tail -20 "$DATA_DIR/logs/postfix.log" 2>/dev/null ||
      journalctl -u postfix -n 20
    echo
    echo "=== Recent Dovecot Logs ==="
    tail -20 "$DATA_DIR/logs/dovecot.log" 2>/dev/null ||
      journalctl -u dovecot -n 20
    ;;
  esac
}

cmd_restart() {
  local service="${1:-all}"

  case $service in
  postfix)
    systemctl restart postfix
    echo "Postfix restarted"
    ;;
  dovecot)
    systemctl restart dovecot
    echo "Dovecot restarted"
    ;;
  all | *)
    systemctl restart postfix dovecot
    systemctl restart opendkim 2>/dev/null || true
    echo "All services restarted"
    ;;
  esac
}

# Main command dispatcher
case "${1:-help}" in
install)
  cmd_install "${2:-}"
  ;;
backup)
  cmd_backup
  ;;
restore)
  cmd_restore "${2:-}"
  ;;
status)
  cmd_status
  ;;
health)
  cmd_health
  ;;
dns-report)
  cmd_dns_report
  ;;
test-email)
  cmd_test_email "${2:-}"
  ;;
add-user)
  cmd_add_user
  ;;
list-users)
  cmd_list_users
  ;;
queue)
  cmd_queue
  ;;
logs)
  cmd_logs "${2:-}"
  ;;
restart)
  cmd_restart "${2:-}"
  ;;
help | --help | -h)
  show_usage
  ;;
*)
  echo "Unknown command: $1"
  echo "Run '$0 help' for usage information"
  exit 1
  ;;
esac

