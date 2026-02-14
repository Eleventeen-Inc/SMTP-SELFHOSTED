# SMTP Mail Server - Dockerized

A production-ready, fully Dockerized mail server running **Postfix**, **Dovecot**, **OpenDKIM**, and **Fail2ban** on Ubuntu 24.04. Deploy a complete email solution on any server with a single command.

## Features

- **Postfix** - SMTP server for sending and receiving email
- **Dovecot** - IMAP/POP3 server for email clients to retrieve mail
- **OpenDKIM** - DKIM signing and verification for email authentication
- **Fail2ban** - Intrusion prevention (auto-bans brute force attacks)
- **Let's Encrypt** - Free automatic SSL/TLS certificates
- **Supervisord** - Process management for all services
- **Environment variables** - Configure everything without editing config files
- **Multi-domain support** - Handle mail for multiple domains
- **Persistent storage** - Docker volumes for mail data, keys, and certificates

## Architecture

```
┌───────────────────────────────────────────────────────┐
│                  Docker Container                     │
│                                                       │
│       ┌──────────┐  ┌─────────┐  ┌──────────┐         │
│       │ Postfix  │  │ Dovecot │  │ OpenDKIM │         │
│       │ (SMTP)   │──│ (IMAP)  │  │ (DKIM)   │         │
│       │ 25/587/  │  │ 143/993 │  │          │         │
│       │ 465      │  │ 110/995 │  │          │         │
│       └──────────┘  └─────────┘  └──────────┘         │
│            │             │            │               │
│       ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│       │Fail2ban  │  │ Rsyslog  │  │Supervisor│        │
│       │(Security)│  │ (Logging)│  │(Manager) │        │
│       └──────────┘  └──────────┘  └──────────┘        │
│                                                       │
│   Volumes: mail-data | ssl-certs | dkim-keys | logs   │
└───────────────────────────────────────────────────────┘
```

## Prerequisites

1. **A server/VPS** with a public IP address (e.g., AWS EC2, DigitalOcean, Hetzner, etc.)
2. **Docker** and **Docker Compose** installed
3. **A domain name** with access to DNS management
4. **Ports open** on your server firewall:
   - `25` (SMTP)
   - `587` (Submission)
   - `465` (SMTPS)
   - `143` (IMAP)
   - `993` (IMAPS)
   - `110` (POP3)
   - `995` (POP3S)
   - `80` (HTTP - for Let's Encrypt)

> **Important:** Many cloud providers (AWS, Azure, GCP) block port 25 by default. You may need to request it to be unblocked.

---

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/Eleventeen-Inc/SMTP-SELFHOSTED.git smtp-server
cd smtp-server
```

### 2. Create Your Environment File

```bash
cp .env.example .env
```

### 3. Edit the `.env` File

Open `.env` in your editor and change the values:

```bash
nano .env
```

**Minimum required changes:**

| Variable | What to Change | Example |
|----------|---------------|---------|
| `MAIL_DOMAIN` | Your domain name | `mydomain.com` |
| `MAIL_HOSTNAME` | Your mail server hostname | `mail.mydomain.com` |
| `SSL_EMAIL` | Your email for Let's Encrypt | `admin@mydomain.com` |
| `MAIL_ACCOUNTS` | Email accounts to create | `admin@mydomain.com:YourStrongPassword123` |

### 4. Set Up DNS Records (Before Starting!)

You **must** configure DNS records before starting the server. See the [DNS Setup](#dns-setup) section below.

### 5. Build and Start

```bash
docker compose up -d --build
```

### 6. Check the Logs

```bash
# View startup logs
docker compose logs -f

# Check if all services are running
docker compose exec mailserver supervisorctl status
```

### 7. Get Your DKIM Key

After the first startup, the DKIM key is generated. Retrieve it:

```bash
docker compose exec mailserver cat /etc/opendkim/keys/<your-domain>/default.txt
```

Add this as a TXT DNS record (see [DNS Setup](#dns-setup)).

---

## Environment Variables Reference

### Domain Settings

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MAIL_DOMAIN` | Yes | `example.com` | Primary mail domain (the part after `@`) |
| `MAIL_HOSTNAME` | Yes | `mail.example.com` | Mail server FQDN (must have DNS A record) |
| `ADDITIONAL_DOMAINS` | No | *(empty)* | Extra domains, comma-separated |

### SSL Settings

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SSL_MODE` | No | `selfsigned` | `letsencrypt`, `selfsigned`, or `manual` |
| `SSL_EMAIL` | For LE | *(auto)* | Email for Let's Encrypt notifications |

### Mail Accounts

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MAIL_ACCOUNTS` | Yes | *(empty)* | Accounts in format `user@domain:password` separated by `\|` |
| `MAIL_ALIASES` | No | *(empty)* | Aliases in format `alias@domain:target@domain` separated by `\|` |

### Advanced

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MESSAGE_SIZE_LIMIT` | No | `52428800` | Max email size in bytes (default 50MB) |
| `TZ` | No | `UTC` | Server timezone |

### Examples

**Single domain, two accounts:**
```env
MAIL_DOMAIN=mydomain.com
MAIL_HOSTNAME=mail.mydomain.com
MAIL_ACCOUNTS=admin@mydomain.com:SuperStr0ng!|info@mydomain.com:An0therP@ss!
MAIL_ALIASES=contact@mydomain.com:admin@mydomain.com|support@mydomain.com:admin@mydomain.com
```

**Multi-domain setup:**
```env
MAIL_DOMAIN=mydomain.com
MAIL_HOSTNAME=mail.mydomain.com
ADDITIONAL_DOMAINS=notification.mydomain.com,alerts.mydomain.com
MAIL_ACCOUNTS=admin@mydomain.com:P@ss1|noreply@notification.mydomain.com:P@ss2
```

---

## DNS Setup

DNS records are **critical** for a working mail server. Without them, your emails will be rejected by other servers.

### Required DNS Records

Set these up in your domain's DNS management panel (Cloudflare, Route53, Namecheap, etc.):

#### 1. A Record (Points hostname to your server IP)

```
Type: A
Name: mail
Value: <YOUR_SERVER_IP>
TTL: 3600
```

#### 2. MX Record (Tells the world where to deliver mail for your domain)

```
Type: MX
Name: @ (or your domain)
Value: mail.yourdomain.com
Priority: 10
TTL: 3600
```

If you have additional domains, add MX records for each:
```
Type: MX
Name: notification (or the subdomain)
Value: mail.yourdomain.com
Priority: 10
TTL: 3600
```

#### 3. SPF Record (Authorizes your server to send mail)

```
Type: TXT
Name: @ (or your domain)
Value: v=spf1 mx a:mail.yourdomain.com ~all
TTL: 3600
```

For additional domains:
```
Type: TXT
Name: notification (or the subdomain)
Value: v=spf1 mx a:mail.yourdomain.com ~all
TTL: 3600
```

#### 4. DKIM Record (Cryptographic email signing)

After starting the container for the first time, get your DKIM key:

```bash
docker compose exec mailserver cat /etc/opendkim/keys/yourdomain.com/default.txt
```

The output will look like:
```
default._domainkey  IN  TXT  ( "v=DKIM1; h=sha256; k=rsa; "
    "p=MIIBIjANBgkqh..." )
```

Add it as a DNS record:
```
Type: TXT
Name: default._domainkey
Value: v=DKIM1; h=sha256; k=rsa; p=MIIBIjANBgkqh...  (the full key)
TTL: 3600
```

> **Note:** Some DNS providers have a character limit for TXT records. You may need to split the value into multiple strings.

#### 5. DMARC Record (Policy for handling failed authentication)

```
Type: TXT
Name: _dmarc
Value: v=DMARC1; p=quarantine; rua=mailto:admin@yourdomain.com; ruf=mailto:admin@yourdomain.com; fo=1
TTL: 3600
```

#### 6. PTR Record / Reverse DNS (Maps IP back to hostname)

This must be set by your hosting provider (not in your domain DNS):

```
IP: <YOUR_SERVER_IP>
PTR: mail.yourdomain.com
```

> **Important:** Without a PTR record, many mail servers (Gmail, Outlook) will reject your emails.

### DNS Record Summary

| Record Type | Name | Value | Purpose |
|------------|------|-------|---------|
| A | `mail` | `YOUR_SERVER_IP` | Server address |
| MX | `@` | `mail.yourdomain.com` (priority 10) | Mail routing |
| TXT | `@` | `v=spf1 mx a:mail.yourdomain.com ~all` | SPF authorization |
| TXT | `default._domainkey` | `v=DKIM1; h=sha256; k=rsa; p=...` | DKIM signing |
| TXT | `_dmarc` | `v=DMARC1; p=quarantine; rua=mailto:...` | DMARC policy |
| PTR | `YOUR_SERVER_IP` | `mail.yourdomain.com` | Reverse DNS |

---

## SSL Certificates

### Option 1: Let's Encrypt (Recommended for Production)

Free, auto-renewing certificates from Let's Encrypt.

**Requirements:**
- Port 80 must be accessible from the internet
- DNS A record for `mail.yourdomain.com` must point to your server
- No other service using port 80

```env
SSL_MODE=letsencrypt
SSL_EMAIL=admin@yourdomain.com
```

**Certificate renewal** happens automatically. The container checks for renewal at startup.

To manually renew:
```bash
docker compose exec mailserver certbot renew
docker compose exec mailserver postfix reload
docker compose exec mailserver dovecot reload
```

### Option 2: Self-Signed (For Testing)

Generates a self-signed certificate automatically. Email clients will show security warnings.

```env
SSL_MODE=selfsigned
```

### Option 3: Manual (Bring Your Own Certificate)

Mount your own certificates into the container.

```env
SSL_MODE=manual
```

Add to `docker-compose.yml` volumes:
```yaml
volumes:
  - ./certs/fullchain.pem:/etc/letsencrypt/live/mail.yourdomain.com/fullchain.pem:ro
  - ./certs/privkey.pem:/etc/letsencrypt/live/mail.yourdomain.com/privkey.pem:ro
```

---

## Managing Email Accounts

### Add Accounts via Environment Variable

The easiest way is to update `.env` and restart:

```env
MAIL_ACCOUNTS=admin@mydomain.com:Pass1|info@mydomain.com:Pass2|newuser@mydomain.com:Pass3
```

```bash
docker compose down
docker compose up -d
```

### Add Accounts Manually (Inside Container)

```bash
# Enter the container
docker compose exec mailserver bash

# Add a new user
NEW_USER="user@yourdomain.com"
NEW_PASS="StrongPassword123"
ENCRYPTED=$(doveadm pw -s SHA512-CRYPT -p "$NEW_PASS")
echo "${NEW_USER}:${ENCRYPTED}" >> /etc/dovecot/users

# Add mailbox mapping
DOMAIN=$(echo "$NEW_USER" | cut -d@ -f2)
USERNAME=$(echo "$NEW_USER" | cut -d@ -f1)
echo "${NEW_USER}    ${DOMAIN}/${USERNAME}/" >> /etc/postfix/virtual_mailbox

# Create mail directory
mkdir -p "/var/mail/vhosts/${DOMAIN}/${USERNAME}"
chown -R vmail:vmail "/var/mail/vhosts/${DOMAIN}/${USERNAME}"

# Rebuild Postfix maps
postmap /etc/postfix/virtual_mailbox

# Reload services
postfix reload
doveadm reload
```

### Change a Password

```bash
docker compose exec mailserver bash

# Generate new encrypted password
NEW_PASS="NewStrongPassword456"
ENCRYPTED=$(doveadm pw -s SHA512-CRYPT -p "$NEW_PASS")

# Edit the users file (replace the line for the target user)
sed -i "s|^user@yourdomain.com:.*|user@yourdomain.com:${ENCRYPTED}|" /etc/dovecot/users

# Reload Dovecot
doveadm reload
```

### Delete an Account

```bash
docker compose exec mailserver bash

# Remove from Dovecot users
sed -i '/^user@yourdomain.com:/d' /etc/dovecot/users

# Remove from Postfix virtual mailbox
sed -i '/^user@yourdomain.com/d' /etc/postfix/virtual_mailbox
postmap /etc/postfix/virtual_mailbox

# Optionally delete mail data
rm -rf /var/mail/vhosts/yourdomain.com/user/

# Reload services
postfix reload
doveadm reload
```

---

## Email Client Configuration

### Incoming Mail (IMAP - Recommended)

| Setting | Value |
|---------|-------|
| Server | `mail.yourdomain.com` |
| Port | `993` |
| Security | SSL/TLS |
| Username | `user@yourdomain.com` (full email) |
| Password | Your password |

### Incoming Mail (POP3)

| Setting | Value |
|---------|-------|
| Server | `mail.yourdomain.com` |
| Port | `995` |
| Security | SSL/TLS |
| Username | `user@yourdomain.com` (full email) |
| Password | Your password |

### Outgoing Mail (SMTP)

| Setting | Value |
|---------|-------|
| Server | `mail.yourdomain.com` |
| Port | `587` (STARTTLS) or `465` (SSL/TLS) |
| Security | STARTTLS (587) or SSL/TLS (465) |
| Authentication | Yes |
| Username | `user@yourdomain.com` (full email) |
| Password | Your password |

---

## Ports Reference

| Port | Protocol | Purpose | Who Uses It |
|------|----------|---------|-------------|
| 25 | SMTP | Receive mail from other servers | Other mail servers |
| 587 | Submission | Send mail (STARTTLS) | Email clients |
| 465 | SMTPS | Send mail (implicit TLS) | Email clients |
| 143 | IMAP | Retrieve mail | Email clients |
| 993 | IMAPS | Retrieve mail (implicit TLS) | Email clients |
| 110 | POP3 | Retrieve mail | Email clients |
| 995 | POP3S | Retrieve mail (implicit TLS) | Email clients |
| 80 | HTTP | Let's Encrypt validation | Certbot |

---

## Docker Volumes

| Volume | Container Path | Purpose |
|--------|---------------|---------|
| `mail-data` | `/var/mail/vhosts` | All email messages (Maildir format) |
| `ssl-certs` | `/etc/letsencrypt` | SSL/TLS certificates |
| `dkim-keys` | `/etc/opendkim/keys` | DKIM signing keys |
| `mail-logs` | `/var/log` | Service logs |

### Backup Volumes

```bash
# Backup all mail data
docker run --rm -v smtp-server_mail-data:/data -v $(pwd):/backup \
  ubuntu tar czf /backup/mail-data-backup.tar.gz -C /data .

# Backup DKIM keys (important - if lost, you must regenerate and update DNS)
docker run --rm -v smtp-server_dkim-keys:/data -v $(pwd):/backup \
  ubuntu tar czf /backup/dkim-keys-backup.tar.gz -C /data .

# Backup SSL certificates
docker run --rm -v smtp-server_ssl-certs:/data -v $(pwd):/backup \
  ubuntu tar czf /backup/ssl-certs-backup.tar.gz -C /data .
```

### Restore Volumes

```bash
# Restore mail data
docker run --rm -v smtp-server_mail-data:/data -v $(pwd):/backup \
  ubuntu bash -c "cd /data && tar xzf /backup/mail-data-backup.tar.gz"
```

---

## Testing

### Test SMTP Connection

```bash
# Test port 25 (from another server)
telnet mail.yourdomain.com 25

# Test with OpenSSL (port 587 STARTTLS)
openssl s_client -starttls smtp -connect mail.yourdomain.com:587

# Test with OpenSSL (port 465 implicit TLS)
openssl s_client -connect mail.yourdomain.com:465
```

### Test IMAP Connection

```bash
# Test IMAPS (port 993)
openssl s_client -connect mail.yourdomain.com:993
```

### Test Email Delivery

```bash
# Send a test email from inside the container
docker compose exec mailserver bash -c '
echo -e "Subject: Test Email
From: admin@yourdomain.com
To: your-external-email@gmail.com

This is a test email from the mail server." | sendmail -f admin@yourdomain.com -t
'
```

### Check DNS Records

```bash
# Check MX record
dig MX yourdomain.com +short

# Check SPF record
dig TXT yourdomain.com +short

# Check DKIM record
dig TXT default._domainkey.yourdomain.com +short

# Check DMARC record
dig TXT _dmarc.yourdomain.com +short

# Check PTR (reverse DNS)
dig -x YOUR_SERVER_IP +short
```

### Online Testing Tools

- [Mail Tester](https://www.mail-tester.com/) - Send a test email and get a spam score
- [MX Toolbox](https://mxtoolbox.com/) - Check DNS records and mail server health
- [DKIM Validator](https://dkimvalidator.com/) - Verify DKIM is working

---

## Troubleshooting

### View Service Status

```bash
docker compose exec mailserver supervisorctl status
```

Expected output:
```
dovecot     RUNNING   pid 123, uptime 0:05:00
fail2ban    RUNNING   pid 124, uptime 0:05:00
opendkim    RUNNING   pid 125, uptime 0:05:00
postfix     RUNNING   pid 126, uptime 0:05:00
rsyslog     RUNNING   pid 127, uptime 0:05:00
```

### View Mail Logs

```bash
# Follow mail log in real-time
docker compose exec mailserver tail -f /var/log/mail.log

# Search for errors
docker compose exec mailserver grep -i error /var/log/mail.log

# View supervisor logs
docker compose exec mailserver tail -f /var/log/supervisor/supervisord.log
```

### Common Issues

#### Emails going to spam

1. **Check PTR record** - Must resolve to `mail.yourdomain.com`
2. **Check SPF record** - Run `dig TXT yourdomain.com`
3. **Check DKIM** - Run `dig TXT default._domainkey.yourdomain.com`
4. **Check DMARC** - Run `dig TXT _dmarc.yourdomain.com`
5. **Test with** [mail-tester.com](https://www.mail-tester.com/)

#### Cannot connect on port 25

- Cloud provider may block port 25 (AWS, Azure, GCP often do)
- Contact your provider to request port 25 to be unblocked
- Check server firewall: `ufw status` or `iptables -L`

#### Let's Encrypt certificate fails

- Ensure port 80 is open and accessible
- Ensure DNS A record for `mail.yourdomain.com` points to your server
- No other service (nginx, apache) is using port 80
- Check with: `curl -I http://mail.yourdomain.com`

#### Cannot authenticate / login fails

- Ensure the password in `MAIL_ACCOUNTS` is correct
- Username must be the full email address (e.g., `admin@yourdomain.com`)
- Check Dovecot logs: `docker compose exec mailserver grep -i auth /var/log/mail.log`

#### Emails not being received

- Check MX record: `dig MX yourdomain.com +short`
- Check port 25 is open: `telnet mail.yourdomain.com 25`
- Check Postfix logs: `docker compose exec mailserver grep -i reject /var/log/mail.log`

---

## Maintenance

### Update the Container

```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```

### Renew SSL Certificate

With `SSL_MODE=letsencrypt`, renewal is automatic at container restart. To force renewal:

```bash
docker compose exec mailserver certbot renew --force-renewal
docker compose exec mailserver postfix reload
docker compose exec mailserver dovecot reload
```

### View Fail2ban Status

```bash
# Check banned IPs
docker compose exec mailserver fail2ban-client status

# Check specific jail
docker compose exec mailserver fail2ban-client status postfix
docker compose exec mailserver fail2ban-client status dovecot

# Unban an IP
docker compose exec mailserver fail2ban-client set postfix unbanip 1.2.3.4
```

### Check Disk Usage

```bash
# Check mail storage size
docker compose exec mailserver du -sh /var/mail/vhosts/

# Check per-domain usage
docker compose exec mailserver du -sh /var/mail/vhosts/*/

# Check log sizes
docker compose exec mailserver du -sh /var/log/mail.*
```

---

## Security Considerations

1. **Use strong passwords** - At least 12 characters with mixed case, numbers, and symbols
2. **Keep the container updated** - Rebuild regularly to get security patches
3. **Monitor logs** - Check for brute force attempts and unusual activity
4. **Backup DKIM keys** - If lost, you must regenerate and update DNS records
5. **Set a proper DMARC policy** - Start with `p=none` for monitoring, then move to `p=quarantine` or `p=reject`
6. **Never expose `.env`** - It contains passwords; it's excluded from Docker builds via `.dockerignore`

---

## File Structure

```
smtp-server/
├── Dockerfile                    # Docker image definition
├── docker-compose.yml            # Container orchestration
├── .env.example                  # Environment variable template
├── .dockerignore                 # Files excluded from Docker build
├── supervisord.conf              # Process manager configuration
├── README.md                     # This file
│
├── scripts/
│   └── entrypoint.sh             # Container startup script
│
├── config/
│   ├── main.cf                   # Postfix main configuration
│   └── master.cf                 # Postfix service definitions
│
├── dovecot/
│   ├── dovecot.conf              # Dovecot main configuration
│   ├── 10-auth.conf              # Authentication settings
│   ├── 10-mail.conf              # Mail storage settings
│   ├── 10-master.conf            # Service/socket definitions
│   ├── 10-ssl.conf               # SSL/TLS configuration
│   └── auth-passwdfile.conf.ext  # Password file backend
│
├── opendkim/
│   ├── opendkim.conf             # OpenDKIM main configuration
│   ├── TrustedHosts              # Trusted hosts for signing
│   ├── KeyTable                  # DKIM key mappings
│   └── SigningTable              # Domain signing rules
│
├── postfix/
│   ├── virtual_domains           # Virtual domain list (auto-generated)
│   ├── virtual_mailbox           # Mailbox mappings (auto-generated)
│   └── virtual                   # Alias mappings (auto-generated)
│
├── default/
│   └── opendkim                  # OpenDKIM daemon defaults
│
├── fail2ban/
│   └── jail.local                # Fail2ban jail configuration
│
├── certificate/
│   └── reload-mail.sh            # SSL renewal hook script
│
└── custom/
    └── custom-mail               # Logrotate configuration
```

---

## Complete Deployment Example

Here is a step-by-step example deploying for `mydomain.com`:

```bash
# 1. SSH into your server
ssh root@your-server-ip

# 2. Install Docker (if not installed)
curl -fsSL https://get.docker.com | sh

# 3. Clone the project
git clone https://github.com/Eleventeen-Inc/SMTP-SELFHOSTED.git /opt/smtp-server
cd /opt/smtp-server

# 4. Create the environment file
cp .env.example .env

# 5. Edit with your actual values
cat > .env << 'EOF'
MAIL_DOMAIN=mydomain.com
MAIL_HOSTNAME=mail.mydomain.com
ADDITIONAL_DOMAINS=
SSL_MODE=letsencrypt
SSL_EMAIL=admin@mydomain.com
MAIL_ACCOUNTS=admin@mydomain.com:MyStr0ngP@ssw0rd!|info@mydomain.com:An0therStr0ngP@ss!
MAIL_ALIASES=contact@mydomain.com:admin@mydomain.com|support@mydomain.com:admin@mydomain.com
MESSAGE_SIZE_LIMIT=52428800
TZ=UTC
EOF

# 6. Build and start
docker compose up -d --build

# 7. Wait 30 seconds for services to initialize
sleep 30

# 8. Check everything is running
docker compose exec mailserver supervisorctl status

# 9. Get your DKIM key and add it to DNS
docker compose exec mailserver cat /etc/opendkim/keys/mydomain.com/default.txt

# 10. Test sending an email
docker compose exec mailserver bash -c '
echo -e "Subject: Test Email
From: admin@mydomain.com
To: test@gmail.com

Hello from my VPS SMTP server!" | sendmail -f admin@mydomain.com -t
'
```

---

## License

This project is licensed under the [MIT License](LICENSE).
