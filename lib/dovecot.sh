#!/bin/bash

# Dovecot configuration functions

configure_dovecot() {
  echo "Configuring Dovecot IMAP/POP3 server..."

  # Backup original configuration
  cp -r /etc/dovecot /etc/dovecot.backup.$(date +%Y%m%d)

  # Main configuration
  cat >/etc/dovecot/dovecot.conf <<EOF
# Dovecot configuration
protocols = imap pop3 lmtp
listen = *, ::
base_dir = /var/run/dovecot/
instance_name = dovecot

# Logging
log_path = $DATA_DIR/logs/dovecot.log
info_log_path = $DATA_DIR/logs/dovecot-info.log
debug_log_path = $DATA_DIR/logs/dovecot-debug.log
log_timestamp = "%Y-%m-%d %H:%M:%S "

# SSL configuration
ssl = required
ssl_cert = <$DATA_DIR/ssl/cert.pem
ssl_key = <$DATA_DIR/ssl/key.pem
ssl_client_ca_dir = /etc/ssl/certs
ssl_dh = <$DATA_DIR/ssl/dh.pem
ssl_min_protocol = TLSv1.2
ssl_cipher_list = ECDHE+AESGCM:ECDHE+RSA+SHA384:ECDHE+RSA+SHA256:ECDHE:DHE+AESGCM:DHE:!PSK:!RSA:!aNULL:!eNULL:!LOW:!3DES:!MD5:!EXP:!SRP:!DSS:!RC4:!SEED
ssl_prefer_server_ciphers = yes

# Mail location and settings
mail_location = maildir:$DATA_DIR/mail/vhosts/%d/%n/Maildir
mail_uid = 5000
mail_gid = 5000
first_valid_uid = 5000
last_valid_uid = 5000
mail_privileged_group = mail

# Authentication
auth_mechanisms = plain login
disable_plaintext_auth = yes

# Namespaces
namespace inbox {
  type = private
  separator = /
  prefix = INBOX/
  inbox = yes
  
  mailbox Drafts {
    auto = subscribe
    special_use = \Drafts
  }
  mailbox Junk {
    auto = subscribe
    special_use = \Junk
  }
  mailbox Trash {
    auto = subscribe
    special_use = \Trash
  }
  mailbox Sent {
    auto = subscribe
    special_use = \Sent
  }
  mailbox "Sent Messages" {
    special_use = \Sent
  }
}

# Include additional configuration files
!include conf.d/*.conf
EOF

  # Authentication configuration
  cat >/etc/dovecot/conf.d/10-auth.conf <<EOF
# Authentication configuration
disable_plaintext_auth = yes
auth_mechanisms = plain login

# Password database
passdb {
  driver = passwd-file
  args = scheme=SHA512-CRYPT username_format=%u /etc/dovecot/users
}

# User database
userdb {
  driver = static
  args = uid=5000 gid=5000 home=$DATA_DIR/mail/vhosts/%d/%n
}

# Authentication socket for Postfix
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0666
    user = postfix
    group = postfix
  }
  
  unix_listener auth-userdb {
    mode = 0666
    user = mail
    group = mail
  }
}

service auth-worker {
  user = mail
}
EOF

  # Master configuration
  cat >/etc/dovecot/conf.d/10-master.conf <<EOF
# Service configuration
service imap-login {
  inet_listener imap {
    port = 143
  }
  inet_listener imaps {
    port = 993
    ssl = yes
  }
  service_count = 1
  process_min_avail = 1
}

service pop3-login {
  inet_listener pop3 {
    port = 110
  }
  inet_listener pop3s {
    port = 995
    ssl = yes
  }
}

service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
  user = mail
}

service imap {
  process_limit = 1024
}

service pop3 {
  process_limit = 1024
}
EOF

  # Mail configuration
  cat >/etc/dovecot/conf.d/10-mail.conf <<EOF
# Mail configuration
mail_location = maildir:$DATA_DIR/mail/vhosts/%d/%n/Maildir
namespace inbox {
  inbox = yes
}
mail_uid = 5000
mail_gid = 5000
mail_privileged_group = mail
mail_access_groups = mail
mail_full_filesystem_access = no

# Mail processes
protocol !indexer-worker {
  mail_vsize_bg_after_count = 100
}

protocol imap {
  mail_plugins = \$mail_plugins imap_quota
  mail_max_userip_connections = 20
  imap_client_workarounds = delay-newmail tb-extra-mailbox-sep
}

protocol pop3 {
  mail_max_userip_connections = 10
  pop3_client_workarounds = outlook-no-nuls oe-ns-eoh
  pop3_uidl_format = %08Xu%08Xv
}

protocol lmtp {
  postmaster_address = postmaster@$HOSTNAME
  mail_plugins = \$mail_plugins
}
EOF

  # SSL configuration
  cat >/etc/dovecot/conf.d/10-ssl.conf <<EOF
# SSL/TLS configuration
ssl = required
ssl_cert = <$DATA_DIR/ssl/cert.pem
ssl_key = <$DATA_DIR/ssl/key.pem
ssl_dh = <$DATA_DIR/ssl/dh.pem
ssl_min_protocol = TLSv1.2
ssl_cipher_list = ECDHE+AESGCM:ECDHE+RSA+SHA384:ECDHE+RSA+SHA256:ECDHE:DHE+AESGCM:DHE:!PSK:!RSA:!aNULL:!eNULL:!LOW:!3DES:!MD5:!EXP:!SRP:!DSS:!RC4:!SEED
ssl_prefer_server_ciphers = yes
EOF

  # Logging configuration
  cat >/etc/dovecot/conf.d/10-logging.conf <<EOF
# Logging configuration
log_path = $DATA_DIR/logs/dovecot.log
info_log_path = $DATA_DIR/logs/dovecot-info.log
debug_log_path = $DATA_DIR/logs/dovecot-debug.log
log_timestamp = "%Y-%m-%d %H:%M:%S "
login_log_format_elements = user=<%u> method=%m rip=%r lip=%l mpid=%e %c
login_log_format = %\$: %s
mail_log_prefix = "%s(%u)<%{pid}><%{session}>: "
deliver_log_format = msgid=%m: %\$
EOF

  # Create mail user if not exists
  if ! id -u mail >/dev/null 2>&1; then
    useradd -r -u 5000 -g mail -d $DATA_DIR/mail -s /sbin/nologin mail
  fi

  # Ensure Postfix socket directory exists
  mkdir -p /var/spool/postfix/private
  chown postfix:postfix /var/spool/postfix/private
  chmod 755 /var/spool/postfix/private

  # Generate DH parameters if not exists
  if [[ ! -f "$DATA_DIR/ssl/dh.pem" ]]; then
    echo "Generating DH parameters (this may take a while)..."
    openssl dhparam -out "$DATA_DIR/ssl/dh.pem" 2048
  fi

  echo "Dovecot configuration completed"
}

configure_sieve() {
  echo "Configuring Sieve filtering..."

  # Install pigeonhole if not present
  case $PKG_MANAGER in
  apt-get)
    apt-get install -y dovecot-sieve dovecot-managesieved
    ;;
  yum)
    yum install -y dovecot-pigeonhole
    ;;
  esac

  # Configure Sieve
  cat >>/etc/dovecot/conf.d/90-sieve.conf <<EOF
# Sieve configuration
plugin {
  sieve = $DATA_DIR/mail/vhosts/%d/%n/.dovecot.sieve
  sieve_global_path = $DATA_DIR/sieve/default.sieve
  sieve_dir = $DATA_DIR/mail/vhosts/%d/%n/sieve
  sieve_global_dir = $DATA_DIR/sieve/global/
}

protocol lmtp {
  mail_plugins = \$mail_plugins sieve
}
EOF

  # Create default sieve script
  mkdir -p "$DATA_DIR/sieve/global"
  cat >"$DATA_DIR/sieve/default.sieve" <<EOF
require ["fileinto", "envelope"];

# File spam into Junk folder
if header :contains "X-Spam-Flag" "YES" {
  fileinto "Junk";
}
EOF

  # Compile the default sieve script
  sievec "$DATA_DIR/sieve/default.sieve"
}

