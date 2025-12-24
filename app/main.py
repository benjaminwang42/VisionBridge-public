import os
import httpx
from typing import Dict, Any
from fastapi import FastAPI, Header, HTTPException, Depends
from dotenv import load_dotenv

load_dotenv()

app = FastAPI()
API_KEY = os.getenv("API_KEY")
CR_API_KEY = os.getenv("CLASH_ROYALE_API_KEY")
CR_API_URL = "https://proxy.royaleapi.dev/v1"

all_small_spells = set(["Mirror", "Arrows", "Zap", "Giant Snowball", "Royal Delivery", "Vines", "Barbarian Barrel", "Goblin Curse", "Rage", "Clone", "Tornado", "Void", "The Log"])
all_big_spells = set(["Fireball", "Rocket", "Earthquake", "Lightning", "Poison", "Freeze"])
all_win_conditions = set(["Graveyard", "Goblin Barrel", "Skeleton Barrel", "Royal Giant", "Mortar", "Elixir Golem", "Battle Ram", "Hog Rider", "Giant", "Royal Hogs", "Three Musketeers", "Wall Breakers", "Goblin Drill", "Balloon", "Goblin Giant", "X-Bow", "Electro Giant", "Golem", "Miner", "Ram Rider", "Lava Hound"])

def verify_api_key(authorization: str = Header(None, description = "Authorization token")):
    if authorization != f"Bearer {API_KEY}":
        raise HTTPException(status_code=401)

@app.get("/health", dependencies=[Depends(verify_api_key)])
def health():
    return {"status": "ok"}

@app.post("/get_deck_by_name", dependencies=[Depends(verify_api_key)])
async def get_deck_by_name(player_data: Dict[Any, Any]):
    args = player_data.get("args", {})
    player_name = args.get("player_name")
    clan_name = args.get("clan_name")
    trophy_count = args.get("trophy_count")

    get_clan_by_name_url = f"{CR_API_URL}/clans"
    get_clan_by_name_params = {
        "name": clan_name,
        "limit": 100
    }

    headers = {
        "Authorization": f"Bearer {CR_API_KEY}"
    }

    async with httpx.AsyncClient() as client:
        try: 
            response = await client.get(get_clan_by_name_url, headers=headers, params=get_clan_by_name_params)
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
            response = await client.get(get_clan_by_id_url, headers=headers)
            response.raise_for_status()
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=500, detail=f"API Error: {e}")
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Internal Server Error: {e}")
        
        clan_data = response.json()
        print("This is the clan data: ", clan_data["memberList"])
        clan_members = clan_data["memberList"]
        print("This is the player_name: ", player_name)
        player_tag = ""
        for member in clan_members:
            if member["name"] == player_name:
                player_tag = member["tag"]
                break
        
        if player_tag == "":
            raise HTTPException(status_code=404, detail="Player not found in clan")

        get_battlelog_by_tag_url = f"{CR_API_URL}/players/{player_tag.replace('#', '%23')}/battlelog"
        try: 
            response = await client.get(get_battlelog_by_tag_url, headers=headers)
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
