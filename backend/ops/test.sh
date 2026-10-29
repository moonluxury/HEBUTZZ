#!/usr/bin/env bash
set -euo pipefail
cd /opt/hegong/backend
runuser -u hegong -- env \
  'DATABASE_URL=dbname=hegong_test user=hegong host=/var/run/postgresql' \
  CURSOR_SECRET=isolated-test-cursor-key-not-for-production \
  CATALOG_PATH=/opt/hegong/backend/collection_catalog.json \
  PYTHONDONTWRITEBYTECODE=1 \
  /opt/hegong/venv/bin/python -m pytest -q -p no:cacheprovider tests
