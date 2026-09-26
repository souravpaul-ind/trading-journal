#!/usr/bin/env python3
"""Automatic sync script - Cron job ke liye"""

import asyncio
import sys
import os
from datetime import datetime

# Path set karo
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from delta_client import fetch_all_filled_orders, fetch_open_positions
from database import (
    group_fills_into_trades, add_grouped_trade,
    add_open_position, remove_closed_open_positions
)


async def auto_sync():
    """Delta se data fetch karke Supabase mein save karta hai"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] Auto-sync started...")

    try:
        # 1. Fills fetch karo
        fills = await fetch_all_filled_orders()
        print(f"  -> {len(fills)} fills fetched")

        # 2. Grouped trades banao
        grouped = group_fills_into_trades(fills)
        print(f"  -> {len(grouped)} grouped trades")

        # 3. Closed open positions remove karo
        removed = remove_closed_open_positions(grouped)
        if removed:
            print(f"  -> {removed} closed positions removed")

        # 4. Grouped trades save karo
        synced = 0
        for trade in grouped:
            try:
                if add_grouped_trade(trade):
                    synced += 1
            except Exception as e:
                print(f"  X Trade skip: {e}")
        print(f"  -> {synced} trades synced")

        # 5. Open positions add karo
        open_positions = await fetch_open_positions()
        open_count = 0
        for pos in open_positions:
            try:
                if add_open_position(pos):
                    open_count += 1
            except Exception as e:
                print(f"  X Position skip: {e}")
        print(f"  -> {open_count} open positions")

        print(f"[{timestamp}] / Auto-sync complete")
        return True

    except Exception as e:
        print(f"[{timestamp}] X Auto-sync failed: {e}")
        import traceback
        traceback.print_exc()
        return False


if __name__ == "__main__":
    asyncio.run(auto_sync())
