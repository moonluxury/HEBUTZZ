"""Post completed three-day sales periods. Safe to rerun after restart or failure."""
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from database import pool, transaction
from wallet_service import settle_commissions


def main():
    pool.open(wait=True)
    try:
        with transaction() as conn:
            result = settle_commissions(conn)
        print(json.dumps(result))
    finally:
        pool.close()


if __name__ == '__main__':
    main()
