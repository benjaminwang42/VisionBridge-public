import os
from dotenv import load_dotenv

load_dotenv()

API_KEY = os.getenv("API_KEY")
CR_API_KEY = os.getenv("CLASH_ROYALE_API_KEY")
PHONE_IP = os.getenv("PHONE_IP")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
CR_API_URL = "https://proxy.royaleapi.dev/v1"

SMALL_SPELLS = {"Mirror", "Arrows", "Zap", "Giant Snowball", "Royal Delivery", "Vines", "Barbarian Barrel", "Goblin Curse", "Rage", "Clone", "Tornado", "Void", "The Log"}
BIG_SPELLS = {"Fireball", "Rocket", "Earthquake", "Lightning", "Poison", "Freeze"}
WIN_CONDITIONS = {"Graveyard", "Goblin Barrel", "Skeleton Barrel", "Royal Giant", "Mortar", "Elixir Golem", "Battle Ram", "Hog Rider", "Giant", "Royal Hogs", "Three Musketeers", "Wall Breakers", "Goblin Drill", "Balloon", "Goblin Giant", "X-Bow", "Electro Giant", "Golem", "Miner", "Ram Rider", "Lava Hound"}