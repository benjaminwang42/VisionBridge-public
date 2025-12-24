import os
from fastapi import FastAPI, Header, HTTPException, Depends
from dotenv import load_dotenv

load_dotenv()

app = FastAPI()
API_KEY = os.getenv("API_KEY")


def verify_api_key(authorization: str = Header(None, description = "Authorization token")):
    if authorization != f"Bearer {API_KEY}":
        raise HTTPException(status_code=401)

@app.get("/health", dependencies=[Depends(verify_api_key)])
def health():
    return {"status": "ok"}
