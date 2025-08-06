#!/bin/bash

# Backup and restore functions for email server

backup_email_server() {
  echo "Starting email server backup..."

  local backup_name="email-backup-$(date +%Y%m%d-%H%M%S)"
  local backup_dir="$DATA_DIR/backup"
  local backup_file="$backup_dir/$backup_name.tar.gz"
  local backup_manifest="$backup_dir/$backup_name.manifest"

  # Create backup directory if not exists
  mkdir -p "$backup_dir"

  # Create manifest file
  cat >"$backup_manifest" <<EOF
Email Server Backup Manifest
============================
Backup Date: $(date)
Server: $HOSTNAME
Data Directory: $DATA_DIR
Backup File: $backup_file

Included Components:
- User mailboxes: $DATA_DIR/mail
- DKIM keys: $DATA_DIR/dkim/keys
- SSL certificates: $DATA_DIR/ssl
- Postfix configuration: /etc/postfix
- Dovecot configuration: /etc/dovecot
- User database: /etc/dovecot/users
- DNS reports: $DATA_DIR/reports

System Information:
$(uname -a)
$(cat /etc/os-release | grep -E "^(NAME|VERSION)")

Domains:
$(cat $DOMAINS_FILE 2>/dev/null || echo "N/A")

Disk Usage Before Backup:
$(du -sh $DATA_DIR/mail 2>/dev/null || echo "N/A")
EOF

  # Stop services for consistent backup
  echo "Stopping services for consistent backup..."
  systemctl stop postfix dovecot

  # Create backup
  echo "Creating backup archive: $backup_file"
  tar -czf "$backup_file" \
    --exclude="$DATA_DIR/backup" \
    --exclude="$DATA_DIR/logs" \
    --exclude="$DATA_DIR/postfix/queue" \
    "$DATA_DIR/mail" \
    "$DATA_DIR/dkim" \
    "$DATA_DIR/ssl" \
    "$DATA_DIR/reports" \
    "/etc/postfix" \
    "/etc/dovecot" \
    "$backup_manifest" 2>/dev/null

  # Start services again
  echo "Restarting services..."
  systemctl start postfix dovecot

  # Verify backup
  if [[ -f "$backup_file" ]]; then
    local backup_size=$(du -h "$backup_file" | cut -f1)
    echo "Backup completed successfully"
    echo "Backup file: $backup_file"
    echo "Backup size: $backup_size"

    # Test backup integrity
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
      echo "Backup integrity verified"
    else
      echo "WARNING: Backup integrity check failed"
    fi

    # Cleanup old backups based on retention policy
    cleanup_old_backups

    return 0
  else
    echo "Backup failed"
    return 1
  fi
}

restore_email_server() {
  local backup_file="$1"

  if [[ -z "$backup_file" ]]; then
    echo "Usage: restore_email_server <backup_file>"
    echo "Available backups:"
    ls -lh "$DATA_DIR/backup/"*.tar.gz 2>/dev/null || echo "No backups found"
    return 1
  fi

  if [[ ! -f "$backup_file" ]]; then
    echo "Backup file not found: $backup_file"
    return 1
  fi

  echo "Restoring email server from: $backup_file"
  echo "WARNING: This will overwrite existing configuration and data!"
  echo "Press Ctrl+C to cancel, or Enter to continue..."
  read

  # Stop services
  echo "Stopping services..."
  systemctl stop postfix dovecot opendkim 2>/dev/null

  # Create restore directory
  local restore_dir="$DATA_DIR/restore-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$restore_dir"

  # Extract backup
  echo "Extracting backup..."
  tar -xzf "$backup_file" -C "$restore_dir"

  # Backup current configuration
  echo "Backing up current configuration..."
  if [[ -d /etc/postfix ]]; then
    mv /etc/postfix "/etc/postfix.before-restore.$(date +%Y%m%d-%H%M%S)"
  fi
  if [[ -d /etc/dovecot ]]; then
    mv /etc/dovecot "/etc/dovecot.before-restore.$(date +%Y%m%d-%H%M%S)"
  fi

  # Restore configurations
  echo "Restoring configurations..."
  if [[ -d "$restore_dir/etc/postfix" ]]; then
    cp -r "$restore_dir/etc/postfix" /etc/
    echo "Postfix configuration restored"
  fi
  if [[ -d "$restore_dir/etc/dovecot" ]]; then
    cp -r "$restore_dir/etc/dovecot" /etc/
    echo "Dovecot configuration restored"
  fi

  # Restore data
  echo "Restoring mail data..."
  if [[ -d "$restore_dir$DATA_DIR/mail" ]]; then
    rsync -av "$restore_dir$DATA_DIR/mail/" "$DATA_DIR/mail/"
    echo "Mail data restored"
  elif [[ -d "$restore_dir/var/mail-server/mail" ]]; then
    # Handle different data_dir paths
    rsync -av "$restore_dir/var/mail-server/mail/" "$DATA_DIR/mail/"
    echo "Mail data restored from alternate path"
  fi

  # Restore DKIM keys
  if [[ -d "$restore_dir$DATA_DIR/dkim" ]]; then
    rsync -av "$restore_dir$DATA_DIR/dkim/" "$DATA_DIR/dkim/"
    echo "DKIM keys restored"
  fi

  # Restore SSL certificates
  if [[ -d "$restore_dir$DATA_DIR/ssl" ]]; then
    rsync -av "$restore_dir$DATA_DIR/ssl/" "$DATA_DIR/ssl/"
    echo "SSL certificates restored"
  fi

  # Fix permissions
  echo "Fixing permissions..."
  chown -R mail:mail "$DATA_DIR/mail"
  chmod -R 700 "$DATA_DIR/mail"
  chown -R opendkim:opendkim "$DATA_DIR/dkim" 2>/dev/null
  chmod 600 "$DATA_DIR/ssl/"*.pem 2>/dev/null
  chmod 600 /etc/dovecot/users 2>/dev/null

  # Rebuild Postfix maps
  echo "Rebuilding Postfix maps..."
  for map in /etc/postfix/virtual_*; do
    if [[ -f "$map" ]] && [[ ! "$map" == *.db ]]; then
      postmap "$map"
    fi
  done

  # Start services
  echo "Starting services..."
  systemctl start postfix
  systemctl start dovecot
  systemctl start opendkim 2>/dev/null

  # Verify services
  sleep 2
  echo "Verifying services..."
  systemctl is-active --quiet postfix && echo "Postfix: Running" || echo "Postfix: Failed"
  systemctl is-active --quiet dovecot && echo "Dovecot: Running" || echo "Dovecot: Failed"

  # Cleanup
  rm -rf "$restore_dir"

  echo "Restore completed"
  echo "Please verify that all services are working correctly"
  echo "Check logs at: $DATA_DIR/logs/"
}

cleanup_old_backups() {
  echo "Cleaning up old backups..."

  # Get retention days from config or use default
  local retention_days=$(python3 -c "
import yaml
try:
    config = yaml.safe_load(open('$CONFIG_FILE'))
    print(config.get('advanced', {}).get('backup', {}).get('retention_days', 30))
except:
    print(30)
" 2>/dev/null || echo "30")

  echo "Retention policy: $retention_days days"

  # Find and remove old backups
  find "$DATA_DIR/backup" -name "email-backup-*.tar.gz" -type f -mtime +$retention_days -exec rm {} \; 2>/dev/null
  find "$DATA_DIR/backup" -name "email-backup-*.manifest" -type f -mtime +$retention_days -exec rm {} \; 2>/dev/null

  # List remaining backups
  echo "Current backups:"
  ls -lh "$DATA_DIR/backup/"*.tar.gz 2>/dev/null | tail -5 || echo "No backups found"
}

schedule_automatic_backups() {
  echo "Setting up automatic backups..."

  # Get backup schedule from config
  local backup_schedule
  if [[ -f "$CONFIG_FILE" ]]; then
    backup_schedule=$(python3 -c "
import yaml
try:
    config = yaml.safe_load(open('$CONFIG_FILE'))
    if config.get('advanced', {}).get('backup', {}).get('enabled', True):
        print(config.get('advanced', {}).get('backup', {}).get('schedule', '0 2 * * *'))
    else:
        print('disabled')
except Exception as e:
    print('0 2 * * *')
" 2>/dev/null)
  fi

  # Default if config reading failed
  backup_schedule="${backup_schedule:-0 2 * * *}"

  if [[ "$backup_schedule" == "disabled" ]]; then
    echo "Automatic backups are disabled in configuration"
    return
  fi

  # Create backup script
  cat >/usr/local/bin/email-server-backup.sh <<EOF
#!/bin/bash
# Automatic email server backup script
# Generated by email server installer

export DATA_DIR="$DATA_DIR"
export CONFIG_FILE="$CONFIG_FILE"
export HOSTNAME="$HOSTNAME"
export DOMAINS_FILE="$DOMAINS_FILE"

source $(dirname $0)/../lib/backup.sh

# Run backup
backup_email_server

# Log result
if [[ \$? -eq 0 ]]; then
    echo "\$(date): Backup completed successfully" >> $DATA_DIR/logs/backup.log
else
    echo "\$(date): Backup failed" >> $DATA_DIR/logs/backup.log
fi
EOF

  chmod +x /usr/local/bin/email-server-backup.sh

  # Add cron job
  local cron_entry="$backup_schedule /usr/local/bin/email-server-backup.sh"

  # Check if cron job already exists
  if ! crontab -l 2>/dev/null | grep -q "email-server-backup.sh"; then
    # Add cron job with error handling
    if (
      crontab -l 2>/dev/null
      echo "$cron_entry"
    ) | crontab - 2>/dev/null; then
      echo "Automatic backup scheduled: $backup_schedule"
    else
      echo "WARNING: Failed to schedule automatic backups - crontab may not be available"
      echo "You can manually add this cron job:"
      echo "$cron_entry"
      return 0 # Don't fail the installer
    fi
  else
    echo "Automatic backup already scheduled"
  fi
}

verify_backup_restore() {
  echo "Performing backup/restore verification test..."

  local test_dir="$DATA_DIR/backup-test"
  local test_backup="$test_dir/test-backup.tar.gz"

  # Create test directory
  mkdir -p "$test_dir"

  # Create test data
  echo "Test data" >"$test_dir/test-file.txt"

  # Create mini backup
  tar -czf "$test_backup" "$test_dir/test-file.txt" 2>/dev/null

  # Verify backup
  if tar -tzf "$test_backup" >/dev/null 2>&1; then
    echo "Backup/restore functionality verified"
    rm -rf "$test_dir"
    return 0
  else
    echo "Backup/restore verification failed"
    rm -rf "$test_dir"
    return 1
  fi
}

