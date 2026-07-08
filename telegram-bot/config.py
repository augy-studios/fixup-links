"""Environment/config loading. Copy .env.example to .env and fill it in."""
from __future__ import annotations

import os

from dotenv import load_dotenv

load_dotenv()

BOT_TOKEN = os.environ.get('BOT_TOKEN', '')
# Used only to build the "@username <link>" example in /start and the docs -
# purely instructional text, not referenced by any command's own logic.
BOT_USERNAME = os.environ.get('BOT_USERNAME', 'uwuFix_bot')
DB_PATH = os.environ.get('DB_PATH', './data/linkfix_bot.sqlite3')
SCHEDULER_DB_PATH = os.environ.get('SCHEDULER_DB_PATH', './data/scheduler.sqlite3')
WEB_APP_URL = os.environ.get('WEB_APP_URL', 'https://fixup.uwuapps.org')
DONATE_URL = os.environ.get('DONATE_URL', 'https://donate.stripe.com/28o2akeAr3hv0DK6oo')
MAX_BATCH_LINKS = int(os.environ.get('MAX_BATCH_LINKS', '30'))
AUTODETECT_DEFAULT = os.environ.get('AUTODETECT_DEFAULT', 'true').lower() in ('1', 'true', 'yes', 'on')
BIO_UPDATE_INTERVAL_MINUTES = int(os.environ.get('BIO_UPDATE_INTERVAL_MINUTES', '30'))

# Only needed if the VPS's network can't reach api.telegram.org directly
# (blocked/throttled at the ISP or hosting-provider level in some regions).
# e.g. socks5://user:pass@host:1080 or http://host:8080. Leave blank to
# connect directly. See SETUP.md's troubleshooting section.
TELEGRAM_PROXY_URL = os.environ.get('TELEGRAM_PROXY_URL', '')
