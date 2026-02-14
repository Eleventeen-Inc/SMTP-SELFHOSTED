#!/bin/bash
# Reload mail services after SSL certificate renewal
# Used as a Let's Encrypt renewal hook

postfix reload
dovecot reload
