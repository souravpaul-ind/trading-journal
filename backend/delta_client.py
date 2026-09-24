import hmac
import hashlib
import time
import httpx
from dotenv import load_dotenv
import os

load_dotenv()

BASE_URL = "https://api.india.delta.exchange"
API_KEY = os.getenv("DELTA_API_KEY")
API_SECRET = os.getenv("DELTA_API_SECRET")

# Root folder mein .env hai, isliye path do
load_dotenv(dotenv_path="../.env")

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
    """Saare purane filled orders fetch karta hai pagination ke saath"""
    all_orders = []
    cursor = None  # pehli baar cursor nahi hoga
    
    async with httpx.AsyncClient(timeout=30.0) as client:
        while True:
            # Cursor ke saath query string banao
            if cursor:
                query_string = f"?state=filled&page_size=50&after={cursor}"
            else:
                query_string = "?state=filled&page_size=50"
            
            method = "GET"
            endpoint = "/v2/orders/history"
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
            
            orders = data.get("result", [])
            all_orders.extend(orders)
            
            # Agla cursor nikalo
            meta = data.get("meta", {})
            cursor = meta.get("after")
            
            # Agar cursor nahi hai to loop khatam
            if not cursor:
                break
    
    return all_orders