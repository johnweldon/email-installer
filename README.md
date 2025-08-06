# Email Server Installer

A comprehensive installer for setting up a production-ready email server with support for multiple domains and users, featuring SMTP, IMAP, and POP3 services.

## Features

- **Multi-domain support** - Handle email for multiple domains
- **User management** - Configure multiple users per domain
- **Modern protocols** - SMTP, IMAP, POP3 with SSL/TLS
- **Security** - DKIM signing, SPF, DMARC support
- **Data portability** - All data in configurable location for easy backup/restore
- **DNS configuration** - Generates complete DNS records (does not create them)
- **Automatic backups** - Scheduled backups with retention policies
- **Service monitoring** - Health checks and status reports

## Quick Start

1. **Clone this repository**

   ```bash
   git clone <repository>
   cd email-installer
   ```

2. **Create configuration**

   ```bash
   cp config.yaml.example config.yaml
   # Edit config.yaml with your domains, users, and settings
   ```

3. **Run installer**

   ```bash
   sudo ./install.sh config.yaml
   ```

4. **Configure DNS**
   - Review the generated DNS records report
   - Add the records to your DNS provider
   - Wait for DNS propagation (usually 24-48 hours)

5. **Verify installation**
   ```bash
   sudo ./manage.sh status
   sudo ./manage.sh test-email admin@yourdomain.com
   ```

## Configuration

The `config.yaml` file controls all aspects of the installation:

```yaml
hostname: mail.example.com # Your mail server's FQDN
data_dir: /var/mail-server # Where all data is stored

domains:
  - name: example.com
    users:
      - username: admin
        password: "SecurePassword123!"
      - username: info
        password: "AnotherSecure456!"
```

See `config.yaml.example` for complete configuration options.

## Management Commands

The `manage.sh` script provides easy access to common tasks:

```bash
# Installation
./manage.sh install [config.yaml]    # Install with configuration

# Backup & Restore
./manage.sh backup                   # Create backup
./manage.sh restore backup.tar.gz    # Restore from backup

# Status & Monitoring
./manage.sh status                   # Show service status
./manage.sh health                   # Check service health
./manage.sh queue                    # View mail queue

# User Management
./manage.sh add-user                 # Add new email user
./manage.sh list-users               # List all users

# DNS & Testing
./manage.sh dns-report               # Generate DNS records
./manage.sh test-email user@domain   # Send test email

# Logs & Services
./manage.sh logs [postfix|dovecot]  # View logs
./manage.sh restart [service]        # Restart services
```

## DNS Configuration

After installation, the installer generates a comprehensive DNS records report that includes:

- **MX Records** - Mail exchange records
- **A/AAAA Records** - Server IP addresses
- **SPF Record** - Sender Policy Framework
- **DKIM Record** - DomainKeys Identified Mail
- **DMARC Record** - Domain-based Message Authentication
- **PTR Record** - Reverse DNS (configure with ISP)
- **SRV Records** - Service discovery (optional)

**Important**: These records are NOT created automatically. You must add them to your DNS provider's control panel.

## Directory Structure

```
/var/mail-server/              # Default data directory
├── mail/                      # User mailboxes
│   └── vhosts/               # Virtual domains
│       └── domain.com/       # Domain directory
│           └── username/     # User maildir
├── ssl/                      # SSL certificates
├── dkim/                     # DKIM keys
│   └── keys/                # Domain DKIM keys
├── postfix/                 # Postfix data
│   └── queue/               # Mail queue
├── dovecot/                 # Dovecot data
├── logs/                    # Service logs
├── backup/                  # Backup files
└── reports/                 # DNS and service reports
```

## Firewall Requirements

Open these ports in your firewall:

| Port | Service    | Purpose                        |
| ---- | ---------- | ------------------------------ |
| 25   | SMTP       | Server-to-server mail transfer |
| 587  | Submission | Client mail submission (TLS)   |
| 465  | SMTPS      | Client mail submission (SSL)   |
| 143  | IMAP       | IMAP access (STARTTLS)         |
| 993  | IMAPS      | IMAP over SSL                  |
| 110  | POP3       | POP3 access (STARTTLS)         |
| 995  | POP3S      | POP3 over SSL                  |
| 80   | HTTP       | Let's Encrypt verification     |

## Backup and Restore

### Automatic Backups

Backups are scheduled automatically during installation (default: daily at 2 AM).

### Manual Backup

```bash
sudo ./manage.sh backup
```

### Restore

```bash
sudo ./manage.sh restore /var/mail-server/backup/email-backup-20240101.tar.gz
```

### What's Backed Up

- User mailboxes
- DKIM keys
- SSL certificates
- Server configurations
- User databases

## Security Considerations

1. **Strong Passwords** - Use complex passwords for all email accounts
2. **SSL/TLS** - Always use encrypted connections
3. **DKIM/SPF/DMARC** - Implement all authentication methods
4. **Regular Updates** - Keep the system and packages updated
5. **Firewall** - Only open necessary ports
6. **Monitoring** - Review logs regularly for suspicious activity

## Troubleshooting

### Check Service Status

```bash
systemctl status postfix dovecot
```

### View Logs

```bash
# Postfix logs
tail -f /var/mail-server/logs/postfix.log

# Dovecot logs
tail -f /var/mail-server/logs/dovecot.log
```

### Test Email Delivery

```bash
echo "Test" | mail -s "Test Subject" user@domain.com
```

### Verify DNS Records

```bash
# Check MX records
dig MX yourdomain.com

# Check SPF
dig TXT yourdomain.com

# Check DKIM
dig TXT mail._domainkey.yourdomain.com

# Check DMARC
dig TXT _dmarc.yourdomain.com
```

### Common Issues

**Cannot send email**

- Check firewall rules for port 25, 587
- Verify DNS records are configured
- Check authentication credentials

**Cannot receive email**

- Verify MX records point to your server
- Check firewall allows port 25
- Review postfix logs for errors

**SSL certificate issues**

- For production, use Let's Encrypt or commercial certificates
- Self-signed certificates will show warnings in email clients

## Requirements

- Linux server (Ubuntu/Debian/CentOS/RHEL)
- Root access
- Static IP address
- Valid domain name
- Open firewall ports

## License

This project is provided as-is for setting up email servers. Use at your own risk.
