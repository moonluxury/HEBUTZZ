"""Operator command: deliver pending publication events to the configured wallet."""
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from database import pool
from publication_rewards import deliver_one

if __name__ == '__main__':
    pool.open(wait=True)
    completed=0
    try:
        while completed<100 and deliver_one(): completed+=1
        print('Confirmed publication credits:',completed)
    finally: pool.close()
