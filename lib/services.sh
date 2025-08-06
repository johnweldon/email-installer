#!/bin/bash

# Service status and reporting functions

generate_service_report() {
  echo "Generating service status report..."

  local report_file="${REPORT_FILE%.dns}.services"

  cat >"$report_file" <<EOF
================================================================================
EMAIL SERVER SERVICE STATUS REPORT
Generated: $(date)
Server: $HOSTNAME
Data Directory: $DATA_DIR
================================================================================

CONFIGURED DOMAINS:
--------------------------------------------------------------------------------
EOF

  # List configured domains
  while IFS= read -r domain; do
    echo "  - $domain" >>"$report_file"
  done <"$DOMAINS_FILE"

  cat >>"$report_file" <<EOF

CONFIGURED USERS:
--------------------------------------------------------------------------------
EOF

  # List configured users
  while IFS=: read -r email password; do
    echo "  - $email" >>"$report_file"
  done <"$USERS_FILE"

  cat >>"$report_file" <<EOF

SERVICE STATUS:
--------------------------------------------------------------------------------
EOF

  # Check Postfix status
  echo "Postfix (SMTP Server):" >>"$report_file"
  if systemctl is-active --quiet postfix; then
    echo "  Status: RUNNING" >>"$report_file"
    echo "  Configuration: /etc/postfix/main.cf" >>"$report_file"
    echo "  Queue Directory: $DATA_DIR/postfix/queue" >>"$report_file"
    postconf -n | head -5 | sed 's/^/  /' >>"$report_file"
  else
    echo "  Status: STOPPED" >>"$report_file"
  fi
  echo "" >>"$report_file"

  # Check Dovecot status
  echo "Dovecot (IMAP/POP3 Server):" >>"$report_file"
  if systemctl is-active --quiet dovecot; then
    echo "  Status: RUNNING" >>"$report_file"
    echo "  Configuration: /etc/dovecot/dovecot.conf" >>"$report_file"
    echo "  Mail Location: $DATA_DIR/mail/vhosts" >>"$report_file"
    doveconf -c /etc/dovecot/dovecot.conf -n | grep -E "^(protocols|ssl|mail_location)" | head -5 | sed 's/^/  /' >>"$report_file"
  else
    echo "  Status: STOPPED" >>"$report_file"
  fi
  echo "" >>"$report_file"

  # Check OpenDKIM status if installed
  if command -v opendkim &>/dev/null; then
    echo "OpenDKIM (DKIM Signing):" >>"$report_file"
    if systemctl is-active --quiet opendkim; then
      echo "  Status: RUNNING" >>"$report_file"
      echo "  Configuration: /etc/opendkim.conf" >>"$report_file"
      echo "  Keys Directory: $DATA_DIR/dkim/keys" >>"$report_file"
    else
      echo "  Status: STOPPED" >>"$report_file"
    fi
    echo "" >>"$report_file"
  fi

  cat >>"$report_file" <<EOF

NETWORK PORTS:
--------------------------------------------------------------------------------
Service         Port    Protocol    Purpose
-------         ----    --------    -------
SMTP            25      TCP         Mail Transfer (Server to Server)
Submission      587     TCP         Mail Submission (Authenticated)
SMTPS           465     TCP         Mail Submission over SSL/TLS
IMAP            143     TCP         IMAP Access (STARTTLS)
IMAPS           993     TCP         IMAP Access over SSL/TLS
POP3            110     TCP         POP3 Access (STARTTLS)
POP3S           995     TCP         POP3 Access over SSL/TLS

ACTIVE LISTENERS:
EOF

  # Show actual listening ports
  if command -v ss &>/dev/null; then
    ss -tlnp 2>/dev/null | grep -E ":(25|587|465|143|993|110|995)\s" | sed 's/^/  /' >>"$report_file" || echo "  No email ports currently listening" >>"$report_file"
  else
    echo "  ss command not available - cannot check listening ports" >>"$report_file"
  fi

  cat >>"$report_file" <<EOF

SSL/TLS CONFIGURATION:
--------------------------------------------------------------------------------
Certificate: $DATA_DIR/ssl/cert.pem
Private Key: $DATA_DIR/ssl/key.pem
DH Parameters: $DATA_DIR/ssl/dh.pem
EOF

  # Check certificate details
  if [[ -f "$DATA_DIR/ssl/cert.pem" ]]; then
    echo "" >>"$report_file"
    echo "Certificate Details:" >>"$report_file"
    openssl x509 -in "$DATA_DIR/ssl/cert.pem" -noout -subject -dates | sed 's/^/  /' >>"$report_file"
  fi

  cat >>"$report_file" <<EOF

DATA STORAGE:
--------------------------------------------------------------------------------
Mail Storage: $DATA_DIR/mail/vhosts
  - Format: Maildir
  - Structure: domain/username/Maildir

Postfix Queue: $DATA_DIR/postfix/queue
Logs: $DATA_DIR/logs
Backups: $DATA_DIR/backup
Reports: $DATA_DIR/reports

DISK USAGE:
EOF

  # Show disk usage
  if [[ -d "$DATA_DIR" && "$(ls -A "$DATA_DIR" 2>/dev/null)" ]]; then
    du -sh "$DATA_DIR"/* 2>/dev/null | sed 's/^/  /' >>"$report_file"
  else
    echo "  Data directory is empty or does not exist" >>"$report_file"
  fi

  cat >>"$report_file" <<EOF

LOG FILES:
--------------------------------------------------------------------------------
Postfix Log: $DATA_DIR/logs/postfix.log
Dovecot Log: $DATA_DIR/logs/dovecot.log
Dovecot Info: $DATA_DIR/logs/dovecot-info.log
Installation Log: /var/log/email-installer.log

AUTHENTICATION METHODS:
--------------------------------------------------------------------------------
SMTP: SASL via Dovecot (PLAIN, LOGIN)
IMAP/POP3: Plain text passwords over TLS
Password Storage: SHA512-CRYPT

SECURITY FEATURES:
--------------------------------------------------------------------------------
- TLS/SSL encryption required for authentication
- DKIM signing for outbound mail
- SPF records (DNS configuration required)
- DMARC policy (DNS configuration required)
- Minimum TLS version: 1.2
- Strong cipher suite configuration
- Authentication required for mail submission

BACKUP RECOMMENDATIONS:
--------------------------------------------------------------------------------
Critical directories to backup:
1. $DATA_DIR/mail - User mailboxes
2. $DATA_DIR/dkim/keys - DKIM private keys
3. $DATA_DIR/ssl - SSL certificates
4. /etc/postfix - Postfix configuration
5. /etc/dovecot - Dovecot configuration

Backup command example:
tar -czf email-backup-\$(date +%Y%m%d).tar.gz \\
    $DATA_DIR/mail \\
    $DATA_DIR/dkim/keys \\
    $DATA_DIR/ssl \\
    /etc/postfix \\
    /etc/dovecot

TROUBLESHOOTING COMMANDS:
--------------------------------------------------------------------------------
# Check mail queue
postqueue -p

# View mail logs
tail -f $DATA_DIR/logs/postfix.log
tail -f $DATA_DIR/logs/dovecot.log

# Test SMTP authentication
openssl s_client -connect localhost:587 -starttls smtp

# Test IMAP connection
openssl s_client -connect localhost:993

# Check service status
systemctl status postfix dovecot

# Verify DNS records
dig MX yourdomain.com
dig TXT yourdomain.com
dig TXT _dmarc.yourdomain.com

# Send test email
echo "Test" | mail -s "Test Subject" user@yourdomain.com

================================================================================
END OF SERVICE STATUS REPORT
================================================================================
EOF

  echo "Service report generated at: $report_file"
}

check_service_health() {
  echo "Performing service health check..."

  local health_ok=true

  # Check Postfix
  if ! systemctl is-active --quiet postfix; then
    echo "WARNING: Postfix is not running"
    health_ok=false
  fi

  # Check Dovecot
  if ! systemctl is-active --quiet dovecot; then
    echo "WARNING: Dovecot is not running"
    health_ok=false
  fi

  # Check ports
  for port in 25 587 993; do
    if command -v ss &>/dev/null && ! ss -tln | grep -q ":$port "; then
      echo "WARNING: Port $port is not listening"
      health_ok=false
    fi
  done

  # Check certificates
  if [[ -f "$DATA_DIR/ssl/cert.pem" ]]; then
    local cert_expiry=$(openssl x509 -in "$DATA_DIR/ssl/cert.pem" -noout -enddate | cut -d= -f2)
    local cert_expiry_epoch=$(date -d "$cert_expiry" +%s)
    local current_epoch=$(date +%s)
    local days_until_expiry=$(((cert_expiry_epoch - current_epoch) / 86400))

    if [[ $days_until_expiry -lt 30 ]]; then
      echo "WARNING: Certificate expires in $days_until_expiry days"
      health_ok=false
    fi
  else
    echo "WARNING: SSL certificate not found"
    health_ok=false
  fi

  if $health_ok; then
    echo "All services are healthy"
    return 0
  else
    echo "Service health check failed"
    return 1
  fi
}

monitor_mail_queue() {
  echo "Mail Queue Status:"
  echo "-----------------"

  # Check Postfix queue
  local queue_count=$(postqueue -p | tail -n1 | grep -oE '[0-9]+' || echo "0")
  echo "Messages in queue: $queue_count"

  if [[ $queue_count -gt 0 ]]; then
    echo "Queue details:"
    postqueue -p | head -20
  fi
}

test_email_delivery() {
  local test_email="${1:-postmaster@$(head -n1 $DOMAINS_FILE)}"

  echo "Testing email delivery to $test_email..."

  # Send test email
  echo "This is a test email from the mail server installer.
Server: $HOSTNAME
Date: $(date)
Configuration test successful." | mail -s "Mail Server Test - $(date +%Y%m%d-%H%M%S)" "$test_email"

  if [[ $? -eq 0 ]]; then
    echo "Test email sent successfully to $test_email"
    echo "Check the inbox and spam folder for the test message"
  else
    echo "Failed to send test email"
  fi
}

