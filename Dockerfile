FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# ============================================
# Install all required packages in one layer
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    postfix postfix-pcre \
    dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd \
    opendkim opendkim-tools \
    certbot \
    fail2ban \
    supervisor \
    rsyslog \
    openssl \
    dns-root-data \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# Create vmail user/group for virtual mailboxes
# ============================================
RUN groupadd -g 5000 vmail && \
    useradd -g vmail -u 5000 vmail -d /var/mail -s /usr/sbin/nologin

# ============================================
# Create required directories
# ============================================
RUN mkdir -p /var/mail/vhosts && \
    chown -R vmail:vmail /var/mail && \
    chmod -R 770 /var/mail && \
    mkdir -p /etc/opendkim/keys && \
    chown -R opendkim:opendkim /etc/opendkim && \
    chmod 750 /etc/opendkim && \
    chmod 700 /etc/opendkim/keys && \
    mkdir -p /run/opendkim && \
    chown opendkim:opendkim /run/opendkim && \
    mkdir -p /var/spool/postfix/private && \
    mkdir -p /var/log/supervisor && \
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy

# ============================================
# Copy Postfix configuration
# ============================================
COPY config/main.cf /etc/postfix/main.cf
COPY config/master.cf /etc/postfix/master.cf

# ============================================
# Copy Dovecot configuration
# ============================================
COPY dovecot/dovecot.conf /etc/dovecot/dovecot.conf
COPY dovecot/10-auth.conf /etc/dovecot/conf.d/10-auth.conf
COPY dovecot/10-mail.conf /etc/dovecot/conf.d/10-mail.conf
COPY dovecot/10-master.conf /etc/dovecot/conf.d/10-master.conf
COPY dovecot/10-ssl.conf /etc/dovecot/conf.d/10-ssl.conf
COPY dovecot/auth-passwdfile.conf.ext /etc/dovecot/conf.d/auth-passwdfile.conf.ext

# Setup Dovecot users file
RUN touch /etc/dovecot/users && \
    chown root:dovecot /etc/dovecot/users && \
    chmod 640 /etc/dovecot/users

# ============================================
# Copy OpenDKIM configuration
# ============================================
COPY opendkim/opendkim.conf /etc/opendkim.conf
COPY opendkim/TrustedHosts /etc/opendkim/TrustedHosts
COPY opendkim/KeyTable /etc/opendkim/KeyTable
COPY opendkim/SigningTable /etc/opendkim/SigningTable
COPY default/opendkim /etc/default/opendkim

# Add postfix user to opendkim group
RUN usermod -aG opendkim postfix

# ============================================
# Copy Postfix virtual mail mappings
# ============================================
COPY postfix/virtual_domains /etc/postfix/virtual_domains
COPY postfix/virtual_mailbox /etc/postfix/virtual_mailbox
COPY postfix/virtual /etc/postfix/virtual

# ============================================
# Copy Fail2ban configuration
# ============================================
COPY fail2ban/jail.local /etc/fail2ban/jail.local

# ============================================
# Copy certificate renewal hook
# ============================================
COPY certificate/reload-mail.sh /etc/letsencrypt/renewal-hooks/deploy/reload-mail.sh
RUN chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-mail.sh

# ============================================
# Copy logrotate configuration
# ============================================
COPY custom/custom-mail /etc/logrotate.d/custom-mail

# ============================================
# Copy supervisor configuration
# ============================================
COPY supervisord.conf /etc/supervisor/conf.d/mail.conf

# ============================================
# Copy and set up entrypoint script
# ============================================
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ============================================
# Expose mail server ports
# ============================================
# 25   = SMTP (server-to-server mail delivery)
# 587  = Submission (client mail submission with STARTTLS)
# 465  = SMTPS (client mail submission with implicit TLS)
# 143  = IMAP (mail retrieval)
# 993  = IMAPS (mail retrieval with implicit TLS)
# 110  = POP3 (mail retrieval)
# 995  = POP3S (mail retrieval with implicit TLS)
# 80   = HTTP (Let's Encrypt certificate validation)
# 443  = HTTPS
EXPOSE 25 587 465 143 993 110 995 80 443

# ============================================
# Health check
# ============================================
HEALTHCHECK --interval=60s --timeout=10s --retries=3 \
    CMD postfix status && doveadm reload 2>/dev/null; exit 0

ENTRYPOINT ["/entrypoint.sh"]
