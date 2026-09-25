import hmac
import hashlib
import time
import httpx
from dotenv import load_dotenv
import os

load_dotenv(dotenv_path="../.env")

BASE_URL = "https://api.india.delta.exchange"
API_KEY = os.getenv("DELTA_API_KEY")
API_SECRET = os.getenv("DELTA_API_SECRET")

# Cache for contract values
_contract_values_cache = None


def generate_signature(method, endpoint, query_string="", payload=""):
    timestamp = str(int(time.time()))
    signature_data = method + timestamp + endpoint + query_string + payload
    signature = hmac.new(
        API_SECRET.encode('utf-8'),
        signature_data.encode('utf-8'),
        hashlib.sha256
    ).hexdigest()
    return signature, timestamp


async def fetch_all_filled_orders():
    """Delta se saare fills fetch karta hai (pagination ke saath)"""
    all_fills = []
    cursor = None

    async with httpx.AsyncClient(timeout=30.0) as client:
        while True:
            if cursor:
                query_string = f"?page_size=100&after={cursor}"
            else:
                query_string = "?page_size=100"

            method = "GET"
            endpoint = "/v2/fills"
            signature, timestamp = generate_signature(method, endpoint, query_string)

            headers = {
                "api-key": API_KEY,
                "signature": signature,
                "timestamp": timestamp,
                "User-Agent": "TradingJournal/1.0"
            }

            resp = await client.get(BASE_URL + endpoint + query_string, headers=headers)
            resp.raise_for_status()
            data = resp.json()

            fills = data.get("result", [])
            all_fills.extend(fills)

            meta = data.get("meta", {})
            cursor = meta.get("after")

            if not cursor:
                break

    return all_fills


async def fetch_contract_values_async():
    """Delta se saare products ka contract_value (lot size) fetch karta hai"""
    global _contract_values_cache
    if _contract_values_cache is not None:
        return _contract_values_cache

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.get(f"{BASE_URL}/v2/products")
        resp.raise_for_status()
        data = resp.json()

        contract_values = {}
        for product in data.get("result", []):
            symbol = product.get("symbol")
            cv = product.get("contract_value")
            if symbol and cv:
                contract_values[symbol] = float(cv)

        _contract_values_cache = contract_values
        return contract_values


def get_contract_value(symbol):
    """Synchronous wrapper — lot size return karta hai.
    API se fetch karta hai, cache mein store karta hai."""
    import asyncio
    try:
        loop = asyncio.get_event_loop()
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

    if loop.is_running():
        import concurrent.futures
        with concurrent.futures.ThreadPoolExecutor() as pool:
            future = pool.submit(asyncio.run, fetch_contract_values_async())
            values = future.result()
    else:
        values = loop.run_until_complete(fetch_contract_values_async())

    return values.get(symbol, 1.0)
