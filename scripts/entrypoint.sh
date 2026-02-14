#!/bin/bash
set -e

# ============================================================
#  SMTP Mail Server - Docker Entrypoint
#  Configures all services using environment variables
# ============================================================

echo "============================================================"
echo "  SMTP Mail Server - Initializing..."
echo "============================================================"

# ----------------------------------------------------------
# Default values for environment variables
# ----------------------------------------------------------
MAIL_DOMAIN="${MAIL_DOMAIN:-example.com}"
MAIL_HOSTNAME="${MAIL_HOSTNAME:-mail.example.com}"
ADDITIONAL_DOMAINS="${ADDITIONAL_DOMAINS:-}"
SSL_EMAIL="${SSL_EMAIL:-admin@${MAIL_DOMAIN}}"
SSL_MODE="${SSL_MODE:-selfsigned}"
MAIL_ACCOUNTS="${MAIL_ACCOUNTS:-}"
MAIL_ALIASES="${MAIL_ALIASES:-}"
MESSAGE_SIZE_LIMIT="${MESSAGE_SIZE_LIMIT:-52428800}"

echo ""
echo "  Configuration:"
echo "  ─────────────────────────────────────────"
echo "  Domain:              ${MAIL_DOMAIN}"
echo "  Hostname:            ${MAIL_HOSTNAME}"
echo "  Additional Domains:  ${ADDITIONAL_DOMAINS:-none}"
echo "  SSL Mode:            ${SSL_MODE}"
echo "  Message Size Limit:  ${MESSAGE_SIZE_LIMIT} bytes"
echo "  ─────────────────────────────────────────"
echo ""

# ===========================================================
# STEP 1: Replace placeholders in configuration files
# ===========================================================
echo "[1/8] Replacing configuration placeholders..."

# --- Postfix main.cf ---
sed -i "s|{{MAIL_HOSTNAME}}|${MAIL_HOSTNAME}|g" /etc/postfix/main.cf
sed -i "s|{{MAIL_DOMAIN}}|${MAIL_DOMAIN}|g" /etc/postfix/main.cf
sed -i "s|{{MESSAGE_SIZE_LIMIT}}|${MESSAGE_SIZE_LIMIT}|g" /etc/postfix/main.cf

# --- Dovecot SSL ---
sed -i "s|{{MAIL_HOSTNAME}}|${MAIL_HOSTNAME}|g" /etc/dovecot/conf.d/10-ssl.conf

# --- OpenDKIM ---
sed -i "s|{{MAIL_DOMAIN}}|${MAIL_DOMAIN}|g" /etc/opendkim.conf
sed -i "s|{{MAIL_DOMAIN}}|${MAIL_DOMAIN}|g" /etc/opendkim/TrustedHosts
sed -i "s|{{MAIL_DOMAIN}}|${MAIL_DOMAIN}|g" /etc/opendkim/KeyTable
sed -i "s|{{MAIL_DOMAIN}}|${MAIL_DOMAIN}|g" /etc/opendkim/SigningTable

# --- Handle additional domains ---
if [ -n "${ADDITIONAL_DOMAINS}" ]; then
    IFS=',' read -ra EXTRA_DOMAINS <<< "${ADDITIONAL_DOMAINS}"
    for domain in "${EXTRA_DOMAINS[@]}"; do
        domain=$(echo "$domain" | xargs)  # trim whitespace

        # Add to TrustedHosts
        echo "${domain}" >> /etc/opendkim/TrustedHosts
        echo "*.${domain}" >> /etc/opendkim/TrustedHosts

        # Add to KeyTable
        echo "default._domainkey.${domain} ${domain}:default:/etc/opendkim/keys/${domain}/default.private" >> /etc/opendkim/KeyTable

        # Add to SigningTable
        echo "*@${domain} default._domainkey.${domain}" >> /etc/opendkim/SigningTable
    done
fi

echo "  Done."

# ===========================================================
# STEP 2: Create mail directories
# ===========================================================
echo "[2/8] Creating mail directories..."

mkdir -p "/var/mail/vhosts/${MAIL_DOMAIN}"

if [ -n "${ADDITIONAL_DOMAINS}" ]; then
    IFS=',' read -ra EXTRA_DOMAINS <<< "${ADDITIONAL_DOMAINS}"
    for domain in "${EXTRA_DOMAINS[@]}"; do
        domain=$(echo "$domain" | xargs)
        mkdir -p "/var/mail/vhosts/${domain}"
    done
fi

chown -R vmail:vmail /var/mail/vhosts
chmod -R 770 /var/mail/vhosts

echo "  Done."

# ===========================================================
# STEP 3: Set up virtual domains
# ===========================================================
echo "[3/8] Setting up virtual domains..."

# Generate virtual_domains file
echo "${MAIL_DOMAIN}  OK" > /etc/postfix/virtual_domains

if [ -n "${ADDITIONAL_DOMAINS}" ]; then
    IFS=',' read -ra EXTRA_DOMAINS <<< "${ADDITIONAL_DOMAINS}"
    for domain in "${EXTRA_DOMAINS[@]}"; do
        domain=$(echo "$domain" | xargs)
        echo "${domain}  OK" >> /etc/postfix/virtual_domains
    done
fi

echo "  Virtual domains configured:"
cat /etc/postfix/virtual_domains | while read line; do echo "    $line"; done

# ===========================================================
# STEP 4: Set up mail accounts
# ===========================================================
echo "[4/8] Setting up mail accounts..."

# Clear existing users
> /etc/dovecot/users
> /etc/postfix/virtual_mailbox

if [ -n "${MAIL_ACCOUNTS}" ]; then
    IFS='|' read -ra ACCOUNTS <<< "${MAIL_ACCOUNTS}"
    for account in "${ACCOUNTS[@]}"; do
        user=$(echo "$account" | cut -d: -f1)
        pass=$(echo "$account" | cut -d: -f2)
        domain=$(echo "$user" | cut -d@ -f2)
        username=$(echo "$user" | cut -d@ -f1)

        # Create encrypted password for Dovecot
        encrypted_pass=$(doveadm pw -s SHA512-CRYPT -p "$pass")
        echo "${user}:${encrypted_pass}" >> /etc/dovecot/users

        # Create Postfix virtual mailbox entry
        echo "${user}    ${domain}/${username}/" >> /etc/postfix/virtual_mailbox

        # Create mail directory
        mkdir -p "/var/mail/vhosts/${domain}/${username}"

        echo "  + Account: ${user}"
    done
else
    echo "  WARNING: No mail accounts configured!"
    echo "  Set MAIL_ACCOUNTS in your .env file."
fi

chown root:dovecot /etc/dovecot/users
chmod 640 /etc/dovecot/users
chown -R vmail:vmail /var/mail/vhosts

# ===========================================================
# STEP 5: Set up mail aliases
# ===========================================================
echo "[5/8] Setting up mail aliases..."

> /etc/postfix/virtual

if [ -n "${MAIL_ALIASES}" ]; then
    IFS='|' read -ra ALIASES <<< "${MAIL_ALIASES}"
    for alias_entry in "${ALIASES[@]}"; do
        alias_from=$(echo "$alias_entry" | cut -d: -f1)
        alias_to=$(echo "$alias_entry" | cut -d: -f2)
        echo "${alias_from}  ${alias_to}" >> /etc/postfix/virtual
        echo "  + Alias: ${alias_from} -> ${alias_to}"
    done
else
    echo "  No aliases configured."
fi

# Create verified_senders map (empty by default, used for sender verification)
touch /etc/postfix/verified_senders
postmap /etc/postfix/verified_senders

# Generate all Postfix lookup maps
postmap /etc/postfix/virtual_domains
postmap /etc/postfix/virtual_mailbox
postmap /etc/postfix/virtual

echo "  Postfix maps generated."

# ===========================================================
# STEP 6: Generate DKIM keys
# ===========================================================
echo "[6/8] Setting up DKIM keys..."

generate_dkim_key() {
    local domain=$1
    local key_dir="/etc/opendkim/keys/${domain}"

    if [ ! -f "${key_dir}/default.private" ]; then
        mkdir -p "${key_dir}"
        opendkim-genkey -b 2048 -s default -d "${domain}" -D "${key_dir}/"
        chown -R opendkim:opendkim "${key_dir}"
        chmod 600 "${key_dir}/default.private"
        echo ""
        echo "  NEW DKIM key generated for: ${domain}"
        echo "  ╔══════════════════════════════════════════════════════════════╗"
        echo "  ║  ADD THIS DNS TXT RECORD for ${domain}:"
        echo "  ╚══════════════════════════════════════════════════════════════╝"
        cat "${key_dir}/default.txt"
        echo ""
    else
        echo "  DKIM key exists for: ${domain} (reusing)"
    fi
}

# Generate key for primary domain
generate_dkim_key "${MAIL_DOMAIN}"

# Generate keys for additional domains
if [ -n "${ADDITIONAL_DOMAINS}" ]; then
    IFS=',' read -ra EXTRA_DOMAINS <<< "${ADDITIONAL_DOMAINS}"
    for domain in "${EXTRA_DOMAINS[@]}"; do
        domain=$(echo "$domain" | xargs)
        generate_dkim_key "${domain}"
    done
fi

chown -R opendkim:opendkim /etc/opendkim
mkdir -p /run/opendkim
chown opendkim:opendkim /run/opendkim

# ===========================================================
# STEP 7: Handle SSL certificates
# ===========================================================
echo "[7/8] Setting up SSL certificates..."

CERT_DIR="/etc/letsencrypt/live/${MAIL_HOSTNAME}"

case "${SSL_MODE}" in
    letsencrypt)
        if [ ! -f "${CERT_DIR}/fullchain.pem" ]; then
            echo "  Obtaining Let's Encrypt certificate for ${MAIL_HOSTNAME}..."
            echo "  (Port 80 must be accessible from the internet)"
            certbot certonly --standalone --non-interactive --agree-tos \
                --email "${SSL_EMAIL}" -d "${MAIL_HOSTNAME}" || {
                echo "  ERROR: Let's Encrypt failed! Falling back to self-signed..."
                mkdir -p "${CERT_DIR}"
                openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
                    -keyout "${CERT_DIR}/privkey.pem" \
                    -out "${CERT_DIR}/fullchain.pem" \
                    -subj "/CN=${MAIL_HOSTNAME}/O=Mail Server/C=US"
            }
        else
            echo "  Let's Encrypt certificate found (reusing)."
            echo "  Running renewal check..."
            certbot renew --quiet || true
        fi
        ;;
    selfsigned)
        if [ ! -f "${CERT_DIR}/fullchain.pem" ]; then
            echo "  Generating self-signed certificate for ${MAIL_HOSTNAME}..."
            mkdir -p "${CERT_DIR}"
            openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
                -keyout "${CERT_DIR}/privkey.pem" \
                -out "${CERT_DIR}/fullchain.pem" \
                -subj "/CN=${MAIL_HOSTNAME}/O=Mail Server/C=US"
            echo "  Self-signed certificate created (valid for 10 years)."
            echo "  NOTE: Self-signed certs will show warnings in email clients."
        else
            echo "  Self-signed certificate found (reusing)."
        fi
        ;;
    manual)
        if [ ! -f "${CERT_DIR}/fullchain.pem" ] || [ ! -f "${CERT_DIR}/privkey.pem" ]; then
            echo "  ERROR: SSL_MODE=manual but no certificates found!"
            echo "  Expected files:"
            echo "    ${CERT_DIR}/fullchain.pem"
            echo "    ${CERT_DIR}/privkey.pem"
            echo ""
            echo "  Mount your certificates or change SSL_MODE."
            echo "  Falling back to self-signed certificate..."
            mkdir -p "${CERT_DIR}"
            openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
                -keyout "${CERT_DIR}/privkey.pem" \
                -out "${CERT_DIR}/fullchain.pem" \
                -subj "/CN=${MAIL_HOSTNAME}/O=Mail Server/C=US"
        else
            echo "  Manual certificate found at ${CERT_DIR}/"
        fi
        ;;
    *)
        echo "  ERROR: Unknown SSL_MODE '${SSL_MODE}'. Use: letsencrypt, selfsigned, or manual"
        exit 1
        ;;
esac

# ===========================================================
# STEP 8: Final setup and start services
# ===========================================================
echo "[8/8] Final setup..."

# Ensure log files exist
touch /var/log/mail.log /var/log/mail.err
chmod 640 /var/log/mail.log /var/log/mail.err

# Ensure Postfix spool directories exist
mkdir -p /var/spool/postfix/private
mkdir -p /var/spool/postfix/public
mkdir -p /var/spool/postfix/pid

# Copy DNS config into Postfix chroot (required for outbound mail delivery)
mkdir -p /var/spool/postfix/etc
cp /etc/resolv.conf /var/spool/postfix/etc/resolv.conf
cp /etc/services /var/spool/postfix/etc/services

# Fix rsyslog for Docker (log to file, not systemd journal)
if [ -f /etc/rsyslog.conf ]; then
    sed -i '/imklog/s/^/#/' /etc/rsyslog.conf
fi

# Ensure proper mail log routing
cat > /etc/rsyslog.d/50-mail.conf << 'RSYSLOG'
mail.*                  -/var/log/mail.log
mail.err                /var/log/mail.err
RSYSLOG

echo "  Permissions set."

echo ""
echo "============================================================"
echo "  SMTP Mail Server - Starting Services"
echo "============================================================"
echo ""
echo "  Services: Postfix, Dovecot, OpenDKIM, Fail2ban, Rsyslog"
echo "  Hostname: ${MAIL_HOSTNAME}"
echo "  Domain:   ${MAIL_DOMAIN}"
echo ""
echo "  SMTP:       25  (server-to-server)"
echo "  Submission: 587 (STARTTLS)"
echo "  SMTPS:      465 (implicit TLS)"
echo "  IMAP:       143 / 993 (TLS)"
echo "  POP3:       110 / 995 (TLS)"
echo ""
echo "============================================================"
echo ""

# Start all services via supervisord
exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/mail.conf
