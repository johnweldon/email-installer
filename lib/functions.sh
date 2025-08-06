#!/bin/bash

# Common functions for email installer

parse_configuration() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    echo "Configuration file not found: $config_file"
    exit 1
  fi

  echo "Parsing configuration from $config_file..."

  # Export configuration as environment variables
  export CONFIG_FILE="$config_file"
  export DATA_DIR=$(python3 -c "import yaml; print(yaml.safe_load(open('$config_file'))['data_dir'])")
  export HOSTNAME=$(python3 -c "import yaml; print(yaml.safe_load(open('$config_file'))['hostname'])")
  export REPORT_FILE="${DATA_DIR}/reports/dns-records-$(date +%Y%m%d-%H%M%S).txt"

  # Create temporary files for parsed data
  export DOMAINS_FILE="/tmp/email-domains-$$"
  export USERS_FILE="/tmp/email-users-$$"
  export CERTS_FILE="/tmp/email-certs-$$"

  # Parse domains
  python3 -c "
import yaml, json
config = yaml.safe_load(open('$config_file'))
for domain in config.get('domains', []):
    print(domain['name'])
" >"$DOMAINS_FILE"

  # Parse users with their domains and passwords
  python3 -c "
import yaml, json
config = yaml.safe_load(open('$config_file'))
for domain in config.get('domains', []):
    for user in domain.get('users', []):
        print(f\"{user['username']}@{domain['name']}:{user['password']}\")
" >"$USERS_FILE"

  # Parse certificates
  python3 -c "
import yaml, json
config = yaml.safe_load(open('$config_file'))
certs = config.get('certificates', {})
if certs:
    print(json.dumps(certs))
" >"$CERTS_FILE"
}

validate_configuration() {
  echo "Validating configuration..."

  # Check required fields
  if [[ -z "$DATA_DIR" ]]; then
    echo "Error: data_dir not specified in configuration"
    exit 1
  fi

  if [[ -z "$HOSTNAME" ]]; then
    echo "Error: hostname not specified in configuration"
    exit 1
  fi

  if [[ ! -s "$DOMAINS_FILE" ]]; then
    echo "Error: No domains configured"
    exit 1
  fi

  if [[ ! -s "$USERS_FILE" ]]; then
    echo "Error: No users configured"
    exit 1
  fi

  echo "Configuration validated successfully"
}

setup_data_directories() {
  echo "Setting up data directories..."

  # Main data directory
  mkdir -p "$DATA_DIR"

  # Mail storage
  mkdir -p "$DATA_DIR/mail"
  mkdir -p "$DATA_DIR/mail/vhosts"

  # Create directory for each domain
  while IFS= read -r domain; do
    mkdir -p "$DATA_DIR/mail/vhosts/$domain"
  done <"$DOMAINS_FILE"

  # Postfix directories
  mkdir -p "$DATA_DIR/postfix"
  mkdir -p "$DATA_DIR/postfix/queue"

  # Dovecot directories
  mkdir -p "$DATA_DIR/dovecot"

  # SSL certificates
  mkdir -p "$DATA_DIR/ssl"

  # Logs
  mkdir -p "$DATA_DIR/logs"

  # Reports
  mkdir -p "$DATA_DIR/reports"

  # Backup directory
  mkdir -p "$DATA_DIR/backup"

  # Set permissions
  chown -R mail:mail "$DATA_DIR/mail"
  chmod -R 700 "$DATA_DIR/mail"

  echo "Data directories created at $DATA_DIR"
}

setup_users_and_domains() {
  echo "Setting up users and domains..."

  # Create virtual mailbox domains file for Postfix
  >/etc/postfix/virtual_domains
  while IFS= read -r domain; do
    echo "$domain OK" >>/etc/postfix/virtual_domains
  done <"$DOMAINS_FILE"
  postmap /etc/postfix/virtual_domains

  # Create virtual mailbox maps for Postfix
  >/etc/postfix/virtual_mailbox
  while IFS=: read -r email password; do
    username="${email%@*}"
    domain="${email#*@}"
    echo "$email $domain/$username/" >>/etc/postfix/virtual_mailbox
  done <"$USERS_FILE"
  postmap /etc/postfix/virtual_mailbox

  # Create password file for Dovecot
  >/etc/dovecot/users
  while IFS=: read -r email password; do
    # Generate password hash
    password_hash=$(doveadm -c /etc/dovecot/dovecot.conf pw -s SHA512-CRYPT -p "$password")
    echo "$email:$password_hash" >>/etc/dovecot/users
  done <"$USERS_FILE"
  chmod 600 /etc/dovecot/users

  # Create mail directories for users
  while IFS=: read -r email password; do
    username="${email%@*}"
    domain="${email#*@}"
    user_dir="$DATA_DIR/mail/vhosts/$domain/$username"
    mkdir -p "$user_dir"
    mkdir -p "$user_dir/Maildir"
    mkdir -p "$user_dir/Maildir/cur"
    mkdir -p "$user_dir/Maildir/new"
    mkdir -p "$user_dir/Maildir/tmp"
    chown -R mail:mail "$user_dir"
  done <"$USERS_FILE"

  echo "Users and domains configured"

  # Preserve configuration files for management script
  cp "$DOMAINS_FILE" "$DATA_DIR/domains.txt"
  cp "$USERS_FILE" "$DATA_DIR/users.txt"
  if [[ -f "$CERTS_FILE" ]]; then
    cp "$CERTS_FILE" "$DATA_DIR/certificates.txt"
  fi

  echo "Configuration files saved to $DATA_DIR"
}

cleanup() {
  # Clean up temporary files
  rm -f "$DOMAINS_FILE" "$USERS_FILE" "$CERTS_FILE"
}

trap cleanup EXIT

