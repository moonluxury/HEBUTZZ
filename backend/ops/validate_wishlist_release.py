"""Test the candidate on its own PostgreSQL database, never the live database."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

PYTHON = '/opt/hegong/venv/bin/python'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate', type=Path)
    args = parser.parse_args()
    candidate = args.candidate.resolve()
    assert os.geteuid() == 0 and candidate.is_relative_to('/opt/hegong/releases')
    manifest_path = candidate / 'wishlist-release.json'
    manifest = json.loads(manifest_path.read_text())
    for name, value in manifest['candidate_sha256'].items():
        assert (candidate / name).resolve().is_relative_to(candidate)
        assert hashlib.sha256((candidate / name).read_bytes()).hexdigest() == value, name
    suffix = candidate.name.rsplit('-', 1)[-1]
    assert re.fullmatch('[0-9a-f]{8}', suffix)
    database = 'hegong_wishlist_' + suffix + '_test'
    subprocess.run(['runuser', '-u', 'postgres', '--', 'createdb', '-O', 'hegong', database], check=True)
    try:
        env = ['DATABASE_URL=dbname=' + database + ' user=hegong host=/var/run/postgresql',
               'CURSOR_SECRET=isolated-wishlist-release-not-production',
               'CATALOG_PATH=' + str(candidate / 'collection_catalog.json'),
               'PYTHONPATH=' + str(candidate), 'PYTHONDONTWRITEBYTECODE=1']
        result = subprocess.run(['runuser', '-u', 'hegong', '--', 'env', *env, PYTHON,
                                 '-m', 'pytest', '-q', '-p', 'no:cacheprovider', '--tb=short', 'tests'],
                                cwd=candidate, capture_output=True, timeout=240)
        (candidate / 'server-tests.log').write_bytes(result.stdout + result.stderr)
        print((result.stdout + result.stderr).decode('utf-8', errors='replace'), flush=True)
        if result.returncode:
            raise RuntimeError('Candidate tests failed; production has not been modified')
        receipt = {'passed': True, 'database': database,
                   'manifest_sha256': hashlib.sha256(manifest_path.read_bytes()).hexdigest()}
        (candidate / 'tests-passed.json').write_text(json.dumps(receipt, indent=2))
    finally:
        assert re.fullmatch('hegong_wishlist_[0-9a-f]{8}_test', database)
        subprocess.run(['runuser', '-u', 'postgres', '--', 'dropdb', database], check=True)


if __name__ == '__main__':
    main()
