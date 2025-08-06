#!/bin/bash

# Certificate management functions

setup_certificates() {
  echo "Setting up SSL certificates..."

  # Check if certificates are provided in config
  if [[ -f "$CERTS_FILE" ]] && [[ -s "$CERTS_FILE" ]]; then
    setup_provided_certificates
  else
    setup_self_signed_certificates
  fi

  # Set proper permissions
  chmod 600 "$DATA_DIR/ssl/"*.pem
  chown root:root "$DATA_DIR/ssl/"*.pem

  echo "SSL certificates configured"
}

setup_provided_certificates() {
  echo "Using provided certificates from configuration..."

  # Parse certificate configuration
  local cert_path=$(python3 -c "
import json
certs = json.load(open('$CERTS_FILE'))
print(certs.get('cert_path', ''))
")

  local key_path=$(python3 -c "
import json
certs = json.load(open('$CERTS_FILE'))
print(certs.get('key_path', ''))
")

  local ca_path=$(python3 -c "
import json
certs = json.load(open('$CERTS_FILE'))
print(certs.get('ca_path', ''))
")

  if [[ -n "$cert_path" ]] && [[ -f "$cert_path" ]]; then
    cp "$cert_path" "$DATA_DIR/ssl/cert.pem"
    echo "Certificate copied from $cert_path"
  else
    echo "Warning: Certificate file not found at $cert_path"
    setup_self_signed_certificates
    return
  fi

  if [[ -n "$key_path" ]] && [[ -f "$key_path" ]]; then
    cp "$key_path" "$DATA_DIR/ssl/key.pem"
    echo "Private key copied from $key_path"
  else
    echo "Warning: Private key file not found at $key_path"
    setup_self_signed_certificates
    return
  fi

  if [[ -n "$ca_path" ]] && [[ -f "$ca_path" ]]; then
    cp "$ca_path" "$DATA_DIR/ssl/ca.pem"
    echo "CA certificate copied from $ca_path"

    # Create full chain
    cat "$DATA_DIR/ssl/cert.pem" "$DATA_DIR/ssl/ca.pem" >"$DATA_DIR/ssl/fullchain.pem"
  else
    echo "Note: CA certificate not provided"
    cp "$DATA_DIR/ssl/cert.pem" "$DATA_DIR/ssl/fullchain.pem"
  fi
}

setup_self_signed_certificates() {
  echo "Generating self-signed certificates..."
  echo "WARNING: Self-signed certificates should only be used for testing!"
  echo "For production, use Let's Encrypt or a commercial certificate."

  # Generate private key
  openssl genrsa -out "$DATA_DIR/ssl/key.pem" 4096

  # Create certificate configuration
  cat >"$DATA_DIR/ssl/cert.conf" <<EOF
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req

[dn]
C=US
ST=State
L=City
O=Organization
OU=Email Server
CN=$HOSTNAME

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $HOSTNAME
EOF

  # Add domain names to alt_names
  local count=2
  while IFS= read -r domain; do
    echo "DNS.$count = $domain" >>"$DATA_DIR/ssl/cert.conf"
    echo "DNS.$((count + 1)) = mail.$domain" >>"$DATA_DIR/ssl/cert.conf"
    count=$((count + 2))
  done <"$DOMAINS_FILE"

  # Generate self-signed certificate
  openssl req -new -x509 -sha256 -days 365 -nodes \
    -key "$DATA_DIR/ssl/key.pem" \
    -out "$DATA_DIR/ssl/cert.pem" \
    -config "$DATA_DIR/ssl/cert.conf"

  # Copy cert as fullchain for self-signed
  cp "$DATA_DIR/ssl/cert.pem" "$DATA_DIR/ssl/fullchain.pem"

  echo "Self-signed certificate generated (valid for 365 days)"
}

setup_letsencrypt() {
  echo "Setting up Let's Encrypt certificates..."

  # Check if certbot is installed
  if ! command -v certbot &>/dev/null; then
    echo "Certbot not found. Installing..."
    case $PKG_MANAGER in
    apt-get)
      apt-get install -y certbot
      ;;
    yum)
      yum install -y certbot
      ;;
    esac
  fi

  # Create webroot directory for acme challenges
  mkdir -p /var/www/html/.well-known/acme-challenge

  # Get primary domain
  local primary_domain=$(head -n1 "$DOMAINS_FILE")

  # Build domain list for certbot
  local domain_args="-d $HOSTNAME"
  while IFS= read -r domain; do
    domain_args="$domain_args -d $domain -d mail.$domain"
  done <"$DOMAINS_FILE"

  echo "Requesting Let's Encrypt certificate for domains..."
  echo "Domains: $domain_args"

  # Request certificate
  certbot certonly \
    --webroot \
    --webroot-path /var/www/html \
    --email "postmaster@$primary_domain" \
    --agree-tos \
    --non-interactive \
    --expand \
    $domain_args

  if [[ $? -eq 0 ]]; then
    # Link certificates
    ln -sf "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" "$DATA_DIR/ssl/cert.pem"
    ln -sf "/etc/letsencrypt/live/$HOSTNAME/privkey.pem" "$DATA_DIR/ssl/key.pem"
    ln -sf "/etc/letsencrypt/live/$HOSTNAME/chain.pem" "$DATA_DIR/ssl/ca.pem"
    ln -sf "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem" "$DATA_DIR/ssl/fullchain.pem"

    echo "Let's Encrypt certificates configured successfully"

    # Setup auto-renewal
    setup_certificate_renewal
  else
    echo "Failed to obtain Let's Encrypt certificate"
    echo "Falling back to self-signed certificate"
    setup_self_signed_certificates
  fi
}

setup_certificate_renewal() {
  echo "Setting up automatic certificate renewal..."

  # Create renewal hook script
  cat >/etc/letsencrypt/renewal-hooks/deploy/mail-server-reload.sh <<'EOF'
#!/bin/bash
systemctl reload postfix
systemctl reload dovecot
EOF

  chmod +x /etc/letsencrypt/renewal-hooks/deploy/mail-server-reload.sh

  # Test renewal
  certbot renew --dry-run

  # Add cron job if not exists
  if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
    (
      crontab -l 2>/dev/null
      echo "0 0,12 * * * /usr/bin/certbot renew --quiet"
    ) | crontab -
    echo "Automatic renewal cron job added"
  fi
}

generate_dh_params() {
  echo "Generating Diffie-Hellman parameters..."

  if [[ ! -f "$DATA_DIR/ssl/dh.pem" ]]; then
    openssl dhparam -out "$DATA_DIR/ssl/dh.pem" 2048
    echo "DH parameters generated"
  else
    echo "DH parameters already exist"
  fi
}

