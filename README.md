<!-- Improved compatibility of back to top link: See: https://github.com/othneildrew/Best-README-Template/pull/73 -->
<a name="readme-top"></a>

<br />
<div align="center">
  <h1 align="center">VisionBridge</h1>

  <p align="center">
    AI voice agent that can parse your phone's screen and perform analysis using the data.
  </p>
</div>

## About The Project

VisionBridge is an AI voice agent that acts as real-time tactical assistant designed for for the game, Clash Royale. The voice agent is able to parse the screen of a mobile phone and uses this to comb through competitive data to give the user an advantage.

Instead of manually searching for an opponent's history, the agent observes your mobile screen, identifies your opponent, and speaks their likely deck composition directly to you. 

This repository only has the endpoints that the AI voice agent uses. It does not have the voice agent logic. 

Key capabilities:
* **Voice Integration**: Delivers intel using a voice agent, enabling the user to access game information without taking their hands off the screen and without a second device.
* **Phone Screen-reading**: ADB screenshot capture of the device screen
* **Screen text parsing**: Gemini OCR for player and clan name detection
* **Deck Analysis**: RoyaleAPI lookups for clan and battlelog

### Built With

* FastAPI
* google-genai
* Pillow
* ADB
* httpx

## Getting Started

Please reach out to me at b83wang@uwaterloo.ca if you would like to learn more about the product or use it.