#!/bin/bash

# DNS records generation functions

generate_dns_report() {
  echo "Generating DNS records report..."

  local report_file="$REPORT_FILE"
  local dkim_selector="mail"

  # Create report header
  cat >"$report_file" <<EOF
================================================================================
DNS RECORDS CONFIGURATION REPORT
Generated: $(date)
Server: $HOSTNAME
================================================================================

IMPORTANT: The following DNS records should be created for your email domains.
These records are not created automatically - you must add them to your DNS
provider's control panel or zone files.

================================================================================

EOF

  # Generate records for each domain
  while IFS= read -r domain; do
    cat >>"$report_file" <<EOF
DOMAIN: $domain
--------------------------------------------------------------------------------

1. MX RECORDS (Mail Exchange)
   Priority  Host                    Points To
   10        $domain                 $HOSTNAME

   DNS Entry:
   $domain.    IN MX 10 $HOSTNAME.

2. A/AAAA RECORDS (IPv4/IPv6 Address)
   Host                    Type    Value
   $HOSTNAME               A       [YOUR_SERVER_IP]
   $HOSTNAME               AAAA    [YOUR_SERVER_IPV6]  (optional)

   DNS Entries:
   $HOSTNAME.    IN A     [YOUR_SERVER_IP]
   $HOSTNAME.    IN AAAA  [YOUR_SERVER_IPV6]

3. SPF RECORD (Sender Policy Framework)
   Host: $domain
   Type: TXT
   Value: "v=spf1 mx a:$HOSTNAME ~all"

   DNS Entry:
   $domain.    IN TXT "v=spf1 mx a:$HOSTNAME ~all"

4. DKIM RECORD (DomainKeys Identified Mail)
EOF

    # Get DKIM public key if it exists
    local dkim_key_file="$DATA_DIR/dkim/keys/$domain/mail.txt"
    if [[ -f "$dkim_key_file" ]]; then
      echo "   Host: ${dkim_selector}._domainkey.$domain" >>"$report_file"
      echo "   Type: TXT" >>"$report_file"
      echo "   Value:" >>"$report_file"

      # Extract the public key from the file
      grep -v "^${dkim_selector}._domainkey" "$dkim_key_file" | sed 's/.*"\(.*\)".*/   "\1"/' >>"$report_file"
      echo "" >>"$report_file"
      echo "   DNS Entry:" >>"$report_file"
      grep -v "^${dkim_selector}._domainkey" "$dkim_key_file" | sed "s/^/   ${dkim_selector}._domainkey.$domain.    IN TXT /" >>"$report_file"
    else
      cat >>"$report_file" <<EOF
   Note: DKIM key not found. Run the installer to generate DKIM keys.
   Host: ${dkim_selector}._domainkey.$domain
   Type: TXT
   Value: [DKIM_PUBLIC_KEY_WILL_BE_GENERATED]
EOF
    fi

    cat >>"$report_file" <<EOF

5. DMARC RECORD (Domain-based Message Authentication)
   Host: _dmarc.$domain
   Type: TXT
   Value: "v=DMARC1; p=quarantine; rua=mailto:postmaster@$domain; ruf=mailto:postmaster@$domain; fo=1; adkim=r; aspf=r; pct=100; rf=afrf; sp=quarantine"

   DNS Entry:
   _dmarc.$domain.    IN TXT "v=DMARC1; p=quarantine; rua=mailto:postmaster@$domain; ruf=mailto:postmaster@$domain; fo=1; adkim=r; aspf=r; pct=100; rf=afrf; sp=quarantine"

   DMARC Policy Explanation:
   - p=quarantine: Quarantine messages that fail DMARC checks
   - rua: Aggregate reports sent to postmaster@$domain
   - ruf: Forensic reports sent to postmaster@$domain
   - adkim=r: Relaxed DKIM alignment
   - aspf=r: Relaxed SPF alignment
   - pct=100: Apply policy to 100% of messages
   - sp=quarantine: Subdomain policy same as domain

6. REVERSE DNS (PTR Record)
   Note: This must be configured with your hosting provider or ISP
   IP Address: [YOUR_SERVER_IP]
   Points To: $HOSTNAME

7. AUTODISCOVER/AUTOCONFIG RECORDS (Optional - for email client autoconfiguration)
   
   For Microsoft Outlook:
   Host: autodiscover.$domain
   Type: CNAME
   Value: $HOSTNAME

   For Thunderbird and other clients:
   Host: autoconfig.$domain
   Type: CNAME
   Value: $HOSTNAME

   DNS Entries:
   autodiscover.$domain.    IN CNAME $HOSTNAME.
   autoconfig.$domain.      IN CNAME $HOSTNAME.

8. SUBMISSION RECORDS (Optional - for explicit mail submission)
   Host: _submission._tcp.$domain
   Type: SRV
   Priority: 0
   Weight: 1
   Port: 587
   Target: $HOSTNAME

   Host: _imaps._tcp.$domain
   Type: SRV
   Priority: 0
   Weight: 1
   Port: 993
   Target: $HOSTNAME

   Host: _pop3s._tcp.$domain
   Type: SRV
   Priority: 0
   Weight: 1
   Port: 995
   Target: $HOSTNAME

   DNS Entries:
   _submission._tcp.$domain.    IN SRV 0 1 587 $HOSTNAME.
   _imaps._tcp.$domain.         IN SRV 0 1 993 $HOSTNAME.
   _pop3s._tcp.$domain.         IN SRV 0 1 995 $HOSTNAME.

================================================================================

EOF
  done <"$DOMAINS_FILE"

  # Add additional notes
  cat >>"$report_file" <<EOF
ADDITIONAL NOTES:
--------------------------------------------------------------------------------

1. IMPORTANT IP ADDRESS CONFIGURATION:
   - Replace [YOUR_SERVER_IP] with your actual server IPv4 address
   - Replace [YOUR_SERVER_IPV6] with your actual server IPv6 address (if available)
   - These values are typically provided by your hosting provider

2. DNS PROPAGATION:
   - DNS changes can take 24-48 hours to propagate globally
   - You can verify DNS records using: dig, nslookup, or online DNS checkers

3. TESTING YOUR CONFIGURATION:
   - SPF: Check with https://www.kitterman.com/spf/validate.html
   - DKIM: Send test email to check-auth@verifier.port25.com
   - DMARC: Use https://dmarcian.com/dmarc-inspector/
   - Overall: Use https://www.mail-tester.com/

4. SECURITY RECOMMENDATIONS:
   - Start with DMARC p=none, monitor reports, then move to p=quarantine
   - Regularly review DMARC reports for authentication failures
   - Keep SPF records under 10 DNS lookups to avoid failures
   - Monitor blacklists at https://mxtoolbox.com/blacklists.aspx

5. FIREWALL REQUIREMENTS:
   The following ports must be open in your firewall:
   - Port 25 (SMTP) - For receiving mail
   - Port 587 (Submission) - For authenticated mail sending
   - Port 465 (SMTPS) - For SSL/TLS mail sending
   - Port 143 (IMAP) - For IMAP access
   - Port 993 (IMAPS) - For SSL/TLS IMAP access
   - Port 110 (POP3) - For POP3 access
   - Port 995 (POP3S) - For SSL/TLS POP3 access

6. BACKUP RECOMMENDATIONS:
   - Regular backups should include: $DATA_DIR
   - Test restore procedures periodically
   - Keep DKIM private keys secure and backed up

================================================================================
END OF DNS RECORDS REPORT
================================================================================
EOF

  echo "DNS records report generated at: $report_file"

  # Also generate BIND zone files
  generate_bind_zone_files
}

generate_bind_zone_files() {
  echo "Generating BIND zone files..."

  local zones_dir="$DATA_DIR/bind-zones"
  mkdir -p "$zones_dir"

  local dkim_selector="mail"

  # Generate zone file for each domain
  while IFS= read -r domain; do
    local zone_file="$zones_dir/db.$domain"

    echo "Creating BIND zone file for $domain at: $zone_file"

    cat >"$zone_file" <<EOF
; BIND Zone File for $domain
; Generated: $(date)
; Email server: $HOSTNAME
;
; IMPORTANT: Replace [YOUR_SERVER_IP] with your actual server IP address
; IMPORTANT: Replace [YOUR_SERVER_IPV6] with your actual IPv6 address (if available)
; IMPORTANT: Adjust the serial number when making changes (format: YYYYMMDDNN)

\$TTL 86400
@       IN SOA  $HOSTNAME. hostmaster.$domain. (
            $(date +%Y%m%d)01    ; Serial (YYYYMMDDNN)
            3600                 ; Refresh
            1800                 ; Retry
            604800               ; Expire
            86400 )              ; Minimum TTL

; Name servers
@       IN NS   $HOSTNAME.

; Mail server A/AAAA records (replace with your actual IP addresses)
$HOSTNAME.      IN A    [YOUR_SERVER_IP]
; $HOSTNAME.    IN AAAA [YOUR_SERVER_IPV6]

; MX record
@       IN MX   10 $HOSTNAME.

; SPF record
@       IN TXT  "v=spf1 mx a:$HOSTNAME ~all"

; DKIM record
EOF

    # Add DKIM record if key exists
    local dkim_key_file="$DATA_DIR/dkim/keys/$domain/mail.txt"
    if [[ -f "$dkim_key_file" ]]; then
      echo "; DKIM public key" >>"$zone_file"
      # Extract the DKIM TXT record content (the part in quotes)
      local dkim_content=$(grep -v "^${dkim_selector}._domainkey" "$dkim_key_file" | sed 's/.*"\(.*\)".*/\1/' | tr -d '\n' | tr -d ' ')
      if [[ -n "$dkim_content" ]]; then
        echo "${dkim_selector}._domainkey IN TXT \"$dkim_content\"" >>"$zone_file"
      else
        echo "; Warning: Could not extract DKIM key from $dkim_key_file" >>"$zone_file"
        echo "${dkim_selector}._domainkey IN TXT \"v=DKIM1; k=rsa; p=[DKIM_KEY_EXTRACTION_FAILED]\"" >>"$zone_file"
      fi
    else
      cat >>"$zone_file" <<EOF
; DKIM public key (to be generated)
${dkim_selector}._domainkey IN TXT "v=DKIM1; k=rsa; p=[DKIM_PUBLIC_KEY_WILL_BE_GENERATED]"
EOF
    fi

    cat >>"$zone_file" <<EOF

; DMARC record
_dmarc  IN TXT  "v=DMARC1; p=quarantine; rua=mailto:postmaster@$domain; ruf=mailto:postmaster@$domain; fo=1; adkim=r; aspf=r; pct=100; rf=afrf; sp=quarantine"

; Email client autoconfiguration (optional)
autodiscover    IN CNAME $HOSTNAME.
autoconfig      IN CNAME $HOSTNAME.

; SRV records for email services (optional)
_submission._tcp    IN SRV  0 1 587 $HOSTNAME.
_imaps._tcp         IN SRV  0 1 993 $HOSTNAME.
_pop3s._tcp         IN SRV  0 1 995 $HOSTNAME.

; Additional A records for subdomains (optional)
; www             IN A    [YOUR_SERVER_IP]
; mail            IN A    [YOUR_SERVER_IP]

EOF

  done <"$DOMAINS_FILE"

  # Create a summary file explaining how to use the zone files
  cat >"$zones_dir/README.txt" <<EOF
BIND Zone Files for Email Domains
=================================
Generated: $(date)

These BIND zone files contain all the DNS records needed for your email domains.

USAGE INSTRUCTIONS:
==================

1. Replace Placeholder Values:
   - Replace [YOUR_SERVER_IP] with your actual server IPv4 address
   - Replace [YOUR_SERVER_IPV6] with your actual server IPv6 address (optional)
   - Update the serial number when making changes (format: YYYYMMDDNN)

2. Install on BIND DNS Server:
   - Copy zone files to your BIND zones directory (usually /var/named/ or /etc/bind/)
   - Add zone declarations to your BIND configuration file (named.conf)

3. Example BIND Configuration (add to named.conf):
EOF

  while IFS= read -r domain; do
    cat >>"$zones_dir/README.txt" <<EOF
   zone "$domain" {
       type master;
       file "db.$domain";
   };
EOF
  done <"$DOMAINS_FILE"

  cat >>"$zones_dir/README.txt" <<EOF

4. After Configuration:
   - Restart BIND: systemctl restart named
   - Check configuration: named-checkconf
   - Check zone files: named-checkzone $domain db.$domain

5. Testing:
   - Test MX records: dig MX yourdomain.com
   - Test SPF records: dig TXT yourdomain.com
   - Test DKIM records: dig TXT mail._domainkey.yourdomain.com
   - Test DMARC records: dig TXT _dmarc.yourdomain.com

FILES IN THIS DIRECTORY:
=======================
EOF

  ls -la "$zones_dir"/db.* >>"$zones_dir/README.txt" 2>/dev/null || echo "No zone files found" >>"$zones_dir/README.txt"

  echo ""
  echo "BIND zone files generated in: $zones_dir"
  echo "README with usage instructions: $zones_dir/README.txt"
}

verify_dns_records() {
  echo "Verifying existing DNS records..."

  local verify_file="${REPORT_FILE%.txt}-verification.txt"

  cat >"$verify_file" <<EOF
================================================================================
DNS RECORDS VERIFICATION REPORT
Generated: $(date)
================================================================================

EOF

  while IFS= read -r domain; do
    echo "Checking DNS records for $domain..." >>"$verify_file"
    echo "----------------------------------------" >>"$verify_file"

    # Check MX records
    echo "MX Records:" >>"$verify_file"
    dig +short MX "$domain" >>"$verify_file" 2>&1 || echo "  Failed to query" >>"$verify_file"
    echo "" >>"$verify_file"

    # Check SPF record
    echo "SPF Record:" >>"$verify_file"
    dig +short TXT "$domain" | grep "v=spf1" >>"$verify_file" 2>&1 || echo "  No SPF record found" >>"$verify_file"
    echo "" >>"$verify_file"

    # Check DKIM record
    echo "DKIM Record:" >>"$verify_file"
    dig +short TXT "mail._domainkey.$domain" >>"$verify_file" 2>&1 || echo "  No DKIM record found" >>"$verify_file"
    echo "" >>"$verify_file"

    # Check DMARC record
    echo "DMARC Record:" >>"$verify_file"
    dig +short TXT "_dmarc.$domain" >>"$verify_file" 2>&1 || echo "  No DMARC record found" >>"$verify_file"
    echo "" >>"$verify_file"

    echo "================================================================================" >>"$verify_file"
    echo "" >>"$verify_file"
  done <"$DOMAINS_FILE"

  echo "DNS verification report generated at: $verify_file"
}

