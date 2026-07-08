"""Environment/config loading. Copy .env.example to .env and fill it in."""
from __future__ import annotations

import os

from dotenv import load_dotenv

load_dotenv()

BOT_TOKEN = os.environ.get('BOT_TOKEN', '')
DB_PATH = os.environ.get('DB_PATH', './data/linkfix_bot.sqlite3')
SCHEDULER_DB_PATH = os.environ.get('SCHEDULER_DB_PATH', './data/scheduler.sqlite3')
WEB_APP_URL = os.environ.get('WEB_APP_URL', 'https://fixup.uwuapps.org')
DONATE_URL = os.environ.get('DONATE_URL', 'https://donate.stripe.com/28o2akeAr3hv0DK6oo')
MAX_BATCH_LINKS = int(os.environ.get('MAX_BATCH_LINKS', '30'))
AUTODETECT_DEFAULT = os.environ.get('AUTODETECT_DEFAULT', 'true').lower() in ('1', 'true', 'yes', 'on')
BIO_UPDATE_INTERVAL_MINUTES = int(os.environ.get('BIO_UPDATE_INTERVAL_MINUTES', '30'))
