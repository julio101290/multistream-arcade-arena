# 🥁 Multistream Arcade Arena

Interactive Python engine (**Pygame + FFmpeg + Ollama**) for simultaneous live streams on **TikTok, Twitch, YouTube, and Facebook**, featuring arcade voting battles, dynamic Ken Burns zoom, a local AI voice host, and automated anti-copyright protection.

![Python](https://img.shields.io/badge/Python-3.10%2B-blue?logo=python&logoColor=white)
![Pygame](https://img.shields.io/badge/Pygame-60%20FPS-green?logo=python&logoColor=white)
![FFmpeg](https://img.shields.io/badge/FFmpeg-Video%20%26%20Audio-orange?logo=ffmpeg&logoColor=white)
![Ollama](https://img.shields.io/badge/Ollama-Local%20AI-purple)
![License](https://img.shields.io/badge/License-MIT-lightgrey)

---

## 🚀 Overview

**Multistream Arcade Arena** turns a folder of vertical or horizontal performance videos (such as drum covers or music sessions) into a **9:16 (`540x960`) interactive arcade game** for live streaming. 

Viewers across four platforms can vote in real time for the next song (`A` or `B`), spawn their profile avatars as orbiting physics bubbles, trigger combos, fire laser attacks with likes/taps, and unleash **Super Votes** using gifts, Bits, or Super Chats.

---

## ✨ Key Features

* **🌐 4-Platform Real-Time Chat Integration:**
  * **TikTok Live:** Connects via `TikTokLive` to capture comments, joins, likes, and gifts (including user profile avatars).
  * **Twitch:** Connects via anonymous IRC (`irc.chat.twitch.tv`) with tag parsing for `first-msg` welcomes and Cheer Bits.
  * **YouTube Live:** Connects via YouTube's InnerTube Live Chat API forced into **"All Messages" mode** so short votes (`a` / `b`) are never filtered out as spam.
  * **Facebook Live:** Polls live stream comments and monitors stream status automatically.
* **🤖 Local AI Host & TTS Narrator (`Ollama`):**
  * Uses a local LLM (`llama3.2:latest` via Ollama) to generate witty, short responses to viewer comments and read them aloud using Mexican Spanish TTS (`es-MX`) with local `.mp3`/`.wav` caching.
  * Includes a smart **Activity Manager** that keeps the stream lively with balanced bot votes and AI-generated chat comments during quiet periods.
* **🎥 Dynamic Visuals & Arcade Physics (60 FPS):**
  * **Ken Burns Slow Zoom:** Smoothly zooms in and out on the background video playback.
  * **Beat-Synced Color Tinting:** Subtle ambient color shifts toward the currently winning team (Fire Orange for **A**, Neon Blue for **B**).
  * **Physics & Particle Engine:** Collision-aware floating avatars, shockwaves, laser projectiles, rising ember particles, and combo counters.
* **🛡️ Multi-Layer Anti-Copyright Protection:**
  * **Preventive Audio Shifting:** Applies a subtle `+3.5%` pitch shift while preserving exact playback tempo (`atempo=0.96618`) via `ffplay`.
  * **Auto-Mute Detection:** Monitors YouTube and Facebook metadata for copyright audio muting and immediately skips the track.
  * **Persistent Blacklist:** Automatically saves flagged tracks to `assets/copyright_blacklist.json` so they are never loaded again.
* **🔊 Zero-Asset Procedural Audio:** Synthesizes all retro arcade sound effects (`.wav`) mathematically at startup—no external audio files required.

---

## 🛠️ Prerequisites & Installation

### 1. System Dependencies (Linux)
Make sure **FFmpeg** (including `ffplay`) is installed on your system:

```bash
# Arch / CachyOS
sudo pacman -S ffmpeg

# Ubuntu / Debian / Linux Mint
sudo apt update && sudo apt install ffmpeg
```

*(Optional)* For local AI chat hosting, install [Ollama](https://ollama.com/) and pull the `llama3.2` model:

```bash
ollama pull llama3.2:latest
```

### 2. Python Dependencies

```bash
git clone [https://github.com/julio101290/multistream-arcade-arena.git](https://github.com/julio101290/multistream-arcade-arena.git)
cd multistream-arcade-arena
pip install pygame pillow requests TikTokLive
```

---

## ⚙️ Configuration

Open the main script and edit the configuration block at the top to match your accounts and local folders:

```python
TIKTOK_USERNAME = "@your_tiktok"
TWITCH_CHANNEL = "your_twitch"
YOUTUBE_CHANNEL_URL = "[https://www.youtube.com/@your_youtube](https://www.youtube.com/@your_youtube)"
FACEBOOK_PAGE_URL = "[https://www.facebook.com/your_facebook/](https://www.facebook.com/your_facebook/)"

VIDEOS_DIR = os.path.expanduser("~/Videos/DrumCovers")
EVASION_COPYRIGHT_AUDIO = True
OLLAMA_MODEL = "llama3.2:latest"
```

---

## 🎮 Usage & OBS Studio Setup

1. Start Ollama in the background (`ollama serve`).
2. Run the application:
   ```bash
   python multistream_drums.py
   ```
3. In **OBS Studio** (or TikTok Live Studio), add a **Window Capture** source targeting the `540x960` Pygame window and scale it to your vertical canvas (`1080x1920`).

### Chat Commands (For Viewers & Moderators)
* `A` / `a` / `1` — Vote for **Option A**
* `B` / `b` / `2` — Vote for **Option B**
* `tap` / `!tap` / `gg` / `fuego` — Fire a rapid laser attack for your team
* **TikTok Likes / Gifts, Twitch Bits, YouTube Super Chats** — Trigger rapid attacks or **Super Votes** (enlarges avatar + shockwave)
* `!copy` / `!copyright` / `!ban` — Immediately blacklist and skip the current song due to copyright

---

## ⌨️ Live Control Hotkeys

Keep the Pygame window focused to trigger manual controls during your broadcast:

| Key | Action |
| :--- | :--- |
| **`A`** / **`1`** | Simulate a vote for **Team A** |
| **`B`** / **`2`** | Simulate a vote for **Team B** |
| **`T`** / **`Space`** | Trigger a rapid laser attack from a random active player |
| **`F`** / **`R`** | Simulate a **Super Vote** (Rose / Bits / Super Chat) |
| **`N`** | End current track and advance to the winning song |
| **`X`** | **Anti-Copyright Panic Button** (permanently blacklists & skips current song) |
| **`I`** | Secretly toggle simulated bot activity ON/OFF |
| **`M`** | Force Ollama AI to generate and read a live chat comment |
| **`V`** | Force the TTS host to announce current voting options |
| **`C`** | Toggle Chroma Key (green screen) background mode |

---

## 👨‍💻 Author & Links

Developed by **Julio César Leyva Rodríguez** ([CesarSystems](https://cesarsystems.com.mx/)):

* **Website:** [cesarsystems.com.mx](https://cesarsystems.com.mx/)
* **Tech Blog:** [shalom-now.blogspot.com](https://shalom-now.blogspot.com/)
* **GitHub:** [@julio101290](https://github.com/julio101290)
* **YouTube:** [@rasec555](https://www.youtube.com/@rasec555) | [@cesarsystems](https://www.youtube.com/@cesarsystems)
* **Telegram:** [t.me/CesarSystems](https://t.me/CesarSystems)
* **Patreon:** [patreon.com/cesarsystems](https://www.patreon.com/cesarsystems)

---

## 📄 License

This project is open-source and available under the **MIT License**.
