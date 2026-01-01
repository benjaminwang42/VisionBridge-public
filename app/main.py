import os
import httpx
import io
import subprocess
import asyncio
from google import genai
from PIL import Image, ImageOps, ImageEnhance
from typing import Dict, Any
from fastapi import FastAPI, Header, HTTPException, Depends
from dotenv import load_dotenv

load_dotenv()

app = FastAPI()
API_KEY = os.getenv("API_KEY")
CR_API_KEY = os.getenv("CLASH_ROYALE_API_KEY")
TAILSCALE_PHONE_IP = os.getenv("PHONE_IP")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

CR_API_URL = "https://proxy.royaleapi.dev/v1"
client = genai.Client(api_key=GEMINI_API_KEY)

all_small_spells = set(["Mirror", "Arrows", "Zap", "Giant Snowball", "Royal Delivery", "Vines", "Barbarian Barrel", "Goblin Curse", "Rage", "Clone", "Tornado", "Void", "The Log"])
all_big_spells = set(["Fireball", "Rocket", "Earthquake", "Lightning", "Poison", "Freeze"])
all_win_conditions = set(["Graveyard", "Goblin Barrel", "Skeleton Barrel", "Royal Giant", "Mortar", "Elixir Golem", "Battle Ram", "Hog Rider", "Giant", "Royal Hogs", "Three Musketeers", "Wall Breakers", "Goblin Drill", "Balloon", "Goblin Giant", "X-Bow", "Electro Giant", "Golem", "Miner", "Ram Rider", "Lava Hound"])

def verify_api_key(authorization: str = Header(None, description = "Authorization token")):
    if authorization != f"Bearer {API_KEY}":
        raise HTTPException(status_code=401)

@app.get("/health", dependencies=[Depends(verify_api_key)])
def health():
    return {"status": "ok"}

@app.post("/get_deck_from_name", dependencies=[Depends(verify_api_key)])
async def get_deck_from_name():
    proxy_prefix = "proxychains4 -f /etc/proxychains4.conf"
    adb_target = f"{TAILSCALE_PHONE_IP}"
    
    connection_result = subprocess.run(
        f"{proxy_prefix} adb connect {adb_target}",
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10
    )
    
    if connection_result.returncode != 0:
        return {
            "error": "ADB connection failed",
            "details": f"Failed to connect: {connection_result.stderr}"
        }

    await asyncio.sleep(2)

    devices_result = subprocess.run(
        f"{proxy_prefix} adb devices",
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    
    if adb_target not in devices_result.stdout or "device" not in devices_result.stdout:
        return {
            "error": "ADB device not connected",
            "details": f"Device {adb_target} not found in adb devices. Output: {devices_result.stdout}"
        }
    try:
        result = subprocess.run(
            f"{proxy_prefix} adb -s {adb_target} exec-out screencap -p",
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
            timeout=10
        )
        
        img = Image.open(io.BytesIO(result.stdout))
    except subprocess.CalledProcessError as e:
        return {"error": "ADB failed. Is the phone screen on?", "details": str(e.stderr)}
    except Exception as e:
        return {"error": str(e)}
    w, h = img.size
    left = w * 0.09
    top = h * 0.07
    right = w * 0.45
    bottom = h * 0.12
    
    crop = img.crop((left, top, right, bottom))

    prompt = "Extract the player name and clan name from this image. Return them as a simple list separated by a comma (e.g., PlayerName, ClanName)."
    try:
        response = client.models.generate_content(
            model="gemini-2.5-flash-lite", 
            contents=[prompt, crop]
        )
        
        raw_text = response.text.strip()
    
        text_parts = [item.strip() for item in raw_text.split(',')]
        player_name = text_parts[0] if len(text_parts) > 0 else "N/A"
        clan_name = text_parts[1] if len(text_parts) > 1 else "N/A"
        print("This is the player name: ", player_name)
        print("This is the clan name: ", clan_name)
    except Exception as e:
        return {"status": "Error", "stage": "Gemini API", "message": str(e)}

    get_clan_by_name_url = f"{CR_API_URL}/clans"
    get_clan_by_name_params = {
        "name": clan_name,
        "limit": 100
    }

    headers = {
        "Authorization": f"Bearer {CR_API_KEY}"
    }

    async with httpx.AsyncClient() as http_client:
        try: 
            response = await http_client.get(get_clan_by_name_url, headers=headers, params=get_clan_by_name_params)
            response.raise_for_status()
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=500, detail=f"API Error: {e}")
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Internal Server Error: {e}")
        
        clans_data = response.json()
        clan_id = ""
        for clan in clans_data["items"]:
            if clan["name"] == clan_name:
                clan_id = clan["tag"]
                break
        
        if clan_id == "":
            raise HTTPException(status_code=404, detail="Clan not found")
        
        get_clan_by_id_url = f"{CR_API_URL}/clans/{clan_id.replace('#', '%23')}"
        try: 
            response = await http_client.get(get_clan_by_id_url, headers=headers)
            response.raise_for_status()
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=500, detail=f"API Error: {e}")
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Internal Server Error: {e}")
        
        clan_data = response.json()
        clan_members = clan_data["memberList"]
        player_tag = ""
        for member in clan_members:
            if member["name"] == player_name:
                player_tag = member["tag"]
                break
        
        if player_tag == "":
            raise HTTPException(status_code=404, detail="Player not found in clan")

        get_battlelog_by_tag_url = f"{CR_API_URL}/players/{player_tag.replace('#', '%23')}/battlelog"
        try: 
            response = await http_client.get(get_battlelog_by_tag_url, headers=headers)
            response.raise_for_status()
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=500, detail=f"API Error: {e}")
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Internal Server Error: {e}")
        
        battlelog_data = response.json()
        last_battle_data = battlelog_data[0]
        deck = last_battle_data["team"][0]["cards"]

        deck = [card["name"] for card in deck]
        
        return {"deck": deck}

@app.post("/get_small_spells", dependencies=[Depends(verify_api_key)])
async def get_small_spells(data: Dict[Any, Any]):
    deck = data['args']['deck']
    return {"small_spells": [card for card in deck if card in all_small_spells]}

@app.post("/get_big_spells", dependencies=[Depends(verify_api_key)])
async def get_big_spells(data: Dict[Any, Any]):
    deck = data['args']['deck']
    return {"big_spells": [card for card in deck if card in all_big_spells]}

@app.post("/get_win_conditions", dependencies=[Depends(verify_api_key)])
async def get_win_conditions(data: Dict[Any, Any]):
    deck = data['args']['deck']
    return {"win_conditions": [card for card in deck if card in all_win_conditions]}
