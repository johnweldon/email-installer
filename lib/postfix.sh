#!/bin/bash

# Postfix configuration functions

configure_postfix() {
  echo "Configuring Postfix SMTP server..."

  # Backup original configuration
  cp /etc/postfix/main.cf /etc/postfix/main.cf.backup.$(date +%Y%m%d)

  # Configure main.cf
  cat >/etc/postfix/main.cf <<EOF
# Basic configuration
myhostname = $HOSTNAME
mydomain = $HOSTNAME
myorigin = \$mydomain
mydestination = localhost
relayhost =
mynetworks = 127.0.0.0/8, [::1]/128
inet_interfaces = all
inet_protocols = all

# Virtual domains and mailboxes
virtual_mailbox_domains = hash:/etc/postfix/virtual_domains
virtual_mailbox_base = $DATA_DIR/mail/vhosts
virtual_mailbox_maps = hash:/etc/postfix/virtual_mailbox
virtual_minimum_uid = 100
virtual_uid_maps = static:5000
virtual_gid_maps = static:5000
virtual_alias_maps = hash:/etc/postfix/virtual_alias

# Security
smtpd_tls_cert_file = $DATA_DIR/ssl/cert.pem
smtpd_tls_key_file = $DATA_DIR/ssl/key.pem
smtpd_tls_security_level = may
smtpd_tls_auth_only = yes
smtpd_tls_protocols = !SSLv2, !SSLv3
smtpd_tls_ciphers = high
smtpd_tls_mandatory_ciphers = high
smtpd_tls_loglevel = 1
smtpd_tls_received_header = yes
smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache

# SASL Authentication
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
broken_sasl_auth_clients = yes

# Restrictions
smtpd_helo_required = yes
smtpd_recipient_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_unauth_destination,
    reject_invalid_hostname,
    reject_non_fqdn_hostname,
    reject_non_fqdn_sender,
    reject_non_fqdn_recipient,
    reject_unknown_sender_domain,
    reject_unknown_recipient_domain,
    reject_rbl_client zen.spamhaus.org,
    permit

smtpd_sender_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_non_fqdn_sender,
    reject_unknown_sender_domain,
    permit

smtpd_relay_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    defer_unauth_destination

# Message size and queue settings
message_size_limit = 52428800
mailbox_size_limit = 0
queue_directory = $DATA_DIR/postfix/queue

# Delivery to Dovecot
virtual_transport = lmtp:unix:private/dovecot-lmtp

# Logging
maillog_file = $DATA_DIR/logs/postfix.log
EOF

  # Configure master.cf for submission and smtps
  cat >>/etc/postfix/master.cf <<EOF

# Submission port 587
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING

# SMTPS port 465
smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
EOF

  # Create virtual alias file
  >/etc/postfix/virtual_alias
  postmap /etc/postfix/virtual_alias

  # Set up DKIM if configured
  setup_dkim

  echo "Postfix configuration completed"
}

setup_dkim() {
  echo "Setting up DKIM..."

  # Check if OpenDKIM is installed
  if ! command -v opendkim &>/dev/null; then
    case $PKG_MANAGER in
    apt-get)
      apt-get install -y opendkim opendkim-tools
      ;;
    yum)
      yum install -y opendkim
      ;;
    esac
  fi

  # Create DKIM directories
  mkdir -p $DATA_DIR/dkim/keys

  # Generate DKIM keys for each domain
  while IFS= read -r domain; do
    echo "Generating DKIM key for $domain..."

    mkdir -p "$DATA_DIR/dkim/keys/$domain"

    # Generate the key
    opendkim-genkey -b 2048 -d "$domain" -D "$DATA_DIR/dkim/keys/$domain" -s mail -v

    # Set permissions
    chown -R opendkim:opendkim "$DATA_DIR/dkim/keys/$domain"
    chmod 600 "$DATA_DIR/dkim/keys/$domain/mail.private"

  done <"$DOMAINS_FILE"

  # Configure OpenDKIM
  cat >/etc/opendkim.conf <<EOF
# OpenDKIM Configuration
AutoRestart             Yes
AutoRestartRate         10/1h
LogWhy                  Yes
Syslog                  Yes
SyslogSuccess           Yes
Mode                    sv
Canonicalization        relaxed/simple
ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable
SignatureAlgorithm      rsa-sha256
Socket                  inet:8891@localhost
PidFile                 /var/run/opendkim/opendkim.pid
UMask                   022
UserID                  opendkim:opendkim
TemporaryDirectory      /var/tmp
EOF

  # Create OpenDKIM directories
  mkdir -p /etc/opendkim

  # TrustedHosts
  cat >/etc/opendkim/TrustedHosts <<EOF
127.0.0.1
localhost
$HOSTNAME
EOF

  # Add domains to TrustedHosts
  while IFS= read -r domain; do
    echo ".$domain" >>/etc/opendkim/TrustedHosts
  done <"$DOMAINS_FILE"

  # KeyTable
  >/etc/opendkim/KeyTable
  while IFS= read -r domain; do
    echo "mail._domainkey.$domain $domain:mail:$DATA_DIR/dkim/keys/$domain/mail.private" >>/etc/opendkim/KeyTable
  done <"$DOMAINS_FILE"

  # SigningTable
  >/etc/opendkim/SigningTable
  while IFS= read -r domain; do
    echo "*@$domain mail._domainkey.$domain" >>/etc/opendkim/SigningTable
  done <"$DOMAINS_FILE"

  # Add DKIM to Postfix
  cat >>/etc/postfix/main.cf <<EOF

# DKIM
milter_protocol = 6
milter_default_action = accept
smtpd_milters = inet:localhost:8891
non_smtpd_milters = inet:localhost:8891
EOF

  # Start OpenDKIM
  systemctl restart opendkim
  systemctl enable opendkim
}

setup_spf() {
  echo "SPF records will be generated in the DNS report"
}

