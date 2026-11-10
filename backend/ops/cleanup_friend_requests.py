#!/usr/bin/env python3
"""Delete expired friend requests and their notifications in bounded transactions."""
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from database import pool, transaction
from friend_request_retention import cleanup_batch


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--batch-size', type=int, default=200, choices=range(1, 1001), metavar='1..1000')
    parser.add_argument('--max-batches', type=int, default=25, choices=range(1, 101), metavar='1..100')
    args = parser.parse_args()
    totals = {'requests': 0, 'notifications': 0, 'receipts': 0, 'batches': 0, 'skipped': False}
    pool.open(wait=True)
    try:
        for _ in range(args.max_batches):
            with transaction() as conn:
                result = cleanup_batch(conn, args.batch_size)
            totals['batches'] += 1
            for key in ('requests', 'notifications', 'receipts'):
                totals[key] += result[key]
            if result['skipped']:
                totals['skipped'] = True
                break
            if max(result['requests'], result['receipts']) < args.batch_size:
                break
        print(json.dumps(totals))
    finally:
        pool.close()


if __name__ == '__main__':
    main()
