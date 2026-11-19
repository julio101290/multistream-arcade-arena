import os
import re
import io
import json
import math
import wave
import struct
import random
import shutil
import socket
import hashlib
import subprocess
import time
import queue
import asyncio
import threading
import requests
import pygame
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from TikTokLive import TikTokLiveClient
from TikTokLive.events import (
    ConnectEvent,
    DisconnectEvent,
    CommentEvent,
    LikeEvent,
    GiftEvent,
    JoinEvent,
)

# ================= CONFIGURACIÓN GENERAL =================
TIKTOK_USERNAME = "@julioleyvarodrigu"                       # Tu cuenta de TikTok
TWITCH_CHANNEL = "bardack21"                                 # Tu cuenta de Twitch
YOUTUBE_CHANNEL_URL = "https://www.youtube.com/@rasec555"    # Tu canal de YouTube
FACEBOOK_PAGE_URL = "https://www.facebook.com/theJulius555/" # Tu página de Facebook

WIDTH, HEIGHT = 540, 960                                     # Formato vertical 9:16
FPS = 60
MAX_BUBBLES_ON_SCREEN = 28                                   # Límite máximo de burbujas simultáneas

# Carpeta de tus videos de batería y archivo de Lista Negra de Copyright
VIDEOS_DIR = os.path.expanduser("~/Vídeos/Videos bateria")
ASSETS_DIR = "assets"
TTS_DIR = os.path.join(ASSETS_DIR, "tts")
BLACKLIST_FILE = os.path.join(ASSETS_DIR, "copyright_blacklist.json")

# Filtro preventivo contra Content ID (micro-ajuste de pitch +3.5% manteniendo duración exacta)
EVASION_COPYRIGHT_AUDIO = True

# Configuración de Ollama (Modelo pequeño de 3B)
OLLAMA_URL = "http://localhost:11434/api/generate"
OLLAMA_MODEL = "llama3.2:latest"

# Configuración de Actividad Automática y Espectadores Conectados (siempre mayor a 30)
MIN_VIEWERS_DISPLAY = 32
BOT_SIMULATION_MINUTES = 5
ENABLE_BOTS = True                                           # Alternar en secreto con la tecla [I]

# Paleta de colores
COLOR_DEMON = (245, 75, 35)                                  # Opción A (Izquierda)
COLOR_DEMON_GLOW = (255, 155, 70)
COLOR_ANGEL = (45, 185, 255)                                 # Opción B (Derecha)
COLOR_ANGEL_GLOW = (155, 230, 255)
COLOR_GOLD = (255, 215, 70)
COLOR_ROSE = (255, 75, 145)
COLOR_TWITCH = (169, 112, 255)                               # Morado Twitch
COLOR_YOUTUBE = (255, 55, 55)                                # Rojo YouTube
COLOR_FACEBOOK = (24, 119, 242)                              # Azul Facebook
COLOR_NEON_GREEN = (80, 255, 140)
CHROMA_GREEN = (0, 255, 0)

ANCHOR_A = [WIDTH * 0.26, HEIGHT * 0.68]
ANCHOR_B = [WIDTH * 0.74, HEIGHT * 0.68]

# Más de 60 usuarios variados para mantener animado el stream
FAKE_USERS_POOL = [
    "carlos_drums90", "sofi_rockera", "el_batero_mx", "metal_head_88",
    "luisa_vibes", "dani_groove", "rock_clasico_fan", "andres_sinaloa",
    "ale_ritmo", "kevin_tama", "valeria_80s", "javi_doublebass",
    "fer_classic", "camila_pop", "diego_baquetas", "leo_thrash",
    "mariana_live", "tono_rocker", "paola_beats", "richie_snare",
    "memo_cymbals", "karen_music", "hugo_bass", "nacho_retro",
    "gaby_estrellas", "sergio_fills", "monica_tempo", "beto_rock77",
    "ivan_paradiddle", "naty_drums", "oscar_zildjian", "brenda_vibes",
    "raul_bombo", "claudia_retro85", "checho_bataca", "elena_rock_mx",
    "pablo_sabian", "lucia_80s_music", "edgar_fill", "vero_indie",
    "ruben_baqueta", "sara_groove", "jorge_hihat", "paty_classic",
    "arturo_pedal", "diana_vinilo", "hector_live99", "miri_acustica",
    "fidel_rockero", "carmen_beats", "gustavo_toms", "lorena_synth",
    "ernesto_drummer", "tania_poprock", "mauricio_stage", "wendy_melodia",
    "ramon_platillos", "jessica_stereo", "omar_redoble", "silvia_cassette",
    "victor_estudio", "adriana_tempo", "alonso_riff", "mayra_conciertos",
]


# ================= GESTOR DE LISTA NEGRA DE COPYRIGHT =================
def load_copyright_blacklist():
    """Carga la lista de canciones prohibidas por copyright para no volver a reproducirlas."""
    os.makedirs(ASSETS_DIR, exist_ok=True)
    if not os.path.exists(BLACKLIST_FILE):
        return set()
    try:
        with open(BLACKLIST_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            return set(data.get("banned_files", []))
    except Exception:
        return set()


def save_to_copyright_blacklist(song_info, reason="Copyright detectado"):
    """Guarda permanentemente una canción en copyright_blacklist.json."""
    if not song_info or not song_info.get("filename"):
        return
    banned = load_copyright_blacklist()
    banned.add(song_info["filename"])
    banned.add(song_info["title"].lower())

    payload = {
        "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "last_reason": f"{song_info['title']} ({reason})",
        "banned_files": sorted(list(banned)),
    }
    try:
        with open(BLACKLIST_FILE, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
        print(f"[ANTI-COPYRIGHT] 🚫 '{song_info['title']}' agregada a la lista negra permanente ({reason}).")
    except Exception as e:
        print(f"[Error guardando Blacklist] {e}")


# ================= DETECTOR DE VOTOS Y COMANDOS DE COPYRIGHT =================
def detectar_voto(comentario: str):
    """
    Detecta el voto por A o B sin importar mayúsculas, minúsculas, signos (!)
    o letras repetidas (ej: 'a', 'A', '!a', 'aaa', 'la a', 'b', 'B', '!b', 'bbb', 'voto b').
    """
    if not comentario:
        return None

    limpio = comentario.strip().lower()
    limpio_letras = re.sub(r"[^a-záéíóúñ0-9\s]", "", limpio).strip()

    if (
        limpio_letras in ("a", "1", "opcion a", "opción a", "voto a", "la a", "voto por la a", "equipo a")
        or re.fullmatch(r"a+", limpio_letras)
        or limpio_letras.startswith("a ")
    ):
        return "A"

    if (
        limpio_letras in ("b", "2", "opcion b", "opción b", "voto b", "la b", "voto por la b", "equipo b")
        or re.fullmatch(r"b+", limpio_letras)
        or limpio_letras.startswith("b ")
    ):
        return "B"

    return None


def es_alerta_copyright_chat(comentario: str):
    """Detecta si se escribe el comando para saltar y bloquear por copyright."""
    if not comentario:
        return False
    c = comentario.strip().lower()
    if c in ("!copy", "!copyright", "!ban", "!mute", "!saltar"):
        return True
    if "copyright" in c and ("mute" in c or "silencio" in c or "bloqueo" in c or "sonido" in c):
        return True
    return False


# ================= ESCANEO Y LIMPIEZA DE VIDEOS =================
def clean_song_title(filename):
    name = os.path.splitext(filename)[0]
    name = re.sub(r"\(\d+\)$", "", name).strip()
    for emoji in ["🖤", "🥁", "⚡", "🔥", "🎸", "🎵", "🎶"]:
        name = name.replace(emoji, "")
    patterns = [
        r"_\s*cover\s*bater[ií]a",
        r"[–\-]\s*drums\s*cover",
        r"drums\s*cover",
        r"cover\s*bater[ií]a",
    ]
    for pat in patterns:
        name = re.sub(pat, "", name, flags=re.IGNORECASE)
    name = re.sub(r"\s+", " ", name).strip(" _-–")
    return name if name else filename


def load_video_library(folder):
    """Carga los videos .mp4 omitiendo duplicados y los que estén en la lista negra de copyright."""
    if not os.path.exists(folder):
        print(f"[Aviso] No se encontró la carpeta: {folder}")
        return []

    blacklist = load_copyright_blacklist()
    files = sorted(f for f in os.listdir(folder) if f.lower().endswith(".mp4"))
    library = []
    seen_titles = set()
    skipped_copy = 0

    for f in files:
        if re.search(r"\(\d+\)\.mp4$", f, flags=re.IGNORECASE):
            continue
        title = clean_song_title(f)
        key = title.lower()

        if f in blacklist or key in blacklist:
            skipped_copy += 1
            continue

        if key not in seen_titles:
            seen_titles.add(key)
            library.append({
                "path": os.path.join(folder, f),
                "title": title,
                "filename": f
            })

    print(f"[Videos] Se cargaron {len(library)} covers válidos ({skipped_copy} excluidos por copyright).")
    return library


# ================= REPRODUCTOR DE VIDEO + AUDIO CON EVASOR CONTENT ID =================
class DrumVideoPlayer:
    def __init__(self, width, height, target_fps=30):
        self.width = width
        self.height = height
        self.target_fps = target_fps
        self.video_proc = None
        self.audio_proc = None
        self.current_surface = None
        self.lock = threading.Lock()
        self.running = False
        self.finished = False
        self.current_song = None

    def play(self, song_info):
        self.stop()
        self.current_song = song_info
        self.finished = False
        self.running = True

        filepath = song_info["path"]
        print(f"[Reproduciendo Ahora] 🥁 {song_info['title']}")

        if shutil.which("ffplay"):
            ffplay_cmd = [
                "ffplay", "-vn", "-nodisp", "-autoexit",
                "-loglevel", "quiet", "-volume", "78"
            ]
            if EVASION_COPYRIGHT_AUDIO:
                ffplay_cmd.extend([
                    "-af", "aresample=44100,asetrate=44100*1.035,aresample=44100,atempo=0.96618"
                ])
            ffplay_cmd.append(filepath)

            self.audio_proc = subprocess.Popen(
                ffplay_cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

        threading.Thread(target=self._video_worker, args=(filepath,), daemon=True).start()

    def _video_worker(self, filepath):
        vf_filter = (
            f"scale={self.width}:{self.height}:force_original_aspect_ratio=decrease,"
            f"pad={self.width}:{self.height}:(ow-iw)/2:(oh-ih)/2:color=100e18"
        )
        cmd = [
            "ffmpeg",
            "-re",
            "-i", filepath,
            "-vf", vf_filter,
            "-r", str(self.target_fps),
            "-f", "rawvideo",
            "-pix_fmt", "rgb24",
            "-loglevel", "quiet",
            "-"
        ]
        frame_size = self.width * self.height * 3
        try:
            self.video_proc = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=frame_size * 2
            )
            while self.running and self.video_proc.poll() is None:
                raw_frame = self.video_proc.stdout.read(frame_size)
                if len(raw_frame) < frame_size:
                    break
                surf = pygame.image.frombuffer(raw_frame, (self.width, self.height), "RGB").convert()
                with self.lock:
                    self.current_surface = surf
        except Exception as e:
            print(f"[Error Video] {e}")
        finally:
            if self.running:
                self.finished = True

    def get_frame(self):
        with self.lock:
            return self.current_surface

    def stop(self):
        self.running = False
        for proc in (self.video_proc, self.audio_proc):
            if proc and proc.poll() is None:
                try:
                    proc.terminate()
                    proc.wait(timeout=0.5)
                except Exception:
                    try:
                        proc.kill()
                    except Exception:
                        pass
        self.video_proc = None
        self.audio_proc = None


# ================= MOTOR DE AUDIO Y NARRADOR TTS + OLLAMA 3B =================
class HybridSound:
    def __init__(self, filepath, volume=0.55, backend="none", pg_sound=None):
        self.filepath = filepath
        self.volume = volume
        self.backend = backend
        self.pg_sound = pg_sound

    def play(self):
        if self.backend == "pygame" and self.pg_sound:
            self.pg_sound.play()
        elif self.backend in ("pw-play", "paplay", "aplay", "ffplay"):
            try:
                if self.backend == "pw-play":
                    cmd = ["pw-play", f"--volume={self.volume:.2f}", self.filepath]
                elif self.backend == "paplay":
                    cmd = ["paplay", f"--volume={int(self.volume * 65536)}", self.filepath]
                elif self.backend == "ffplay":
                    cmd = ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", self.filepath]
                else:
                    cmd = ["aplay", "-q", self.filepath]
                subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass


class AudioManager:
    def __init__(self):
        self.backend = "none"
        try:
            pygame.mixer.init(frequency=44100, size=-16, channels=2, buffer=512)
            self.backend = "pygame"
            print("[Audio] Usando pygame.mixer.")
        except Exception:
            for tool in ("pw-play", "paplay", "ffplay", "aplay"):
                if shutil.which(tool):
                    self.backend = tool
                    print(f"[Audio] Usando '{tool}' nativo de Linux para efectos.")
                    break

    def load_sound(self, filepath, volume=0.55):
        if self.backend == "pygame":
            snd = pygame.mixer.Sound(filepath)
            snd.set_volume(volume)
            return HybridSound(filepath, volume, "pygame", snd)
        return HybridSound(filepath, volume, self.backend)


class NarratorTTS:
    def __init__(self):
        os.makedirs(TTS_DIR, exist_ok=True)
        self.q = queue.Queue()
        self.llm_q = queue.Queue()
        self.bot_comment_q = queue.Queue()
        self.current_subtitle = ""
        self.speaking = False
        self.last_join_tts = 0.0
        self.last_comment_llm = 0.0
        self.has_ffmpeg = shutil.which("ffmpeg") is not None
        self.has_ffplay = shutil.which("ffplay") is not None
        self.has_pwplay = shutil.which("pw-play") is not None
        self.has_paplay = shutil.which("paplay") is not None
        self.has_mpv = shutil.which("mpv") is not None
        self.has_espeak = shutil.which("espeak-ng") or shutil.which("espeak")

        threading.Thread(target=self._tts_worker, daemon=True).start()
        threading.Thread(target=self._ollama_reply_worker, daemon=True).start()
        threading.Thread(target=self._ollama_fake_comment_worker, daemon=True).start()

    def say(self, text, priority=False):
        if not text:
            return
        if priority:
            while not self.q.empty():
                try:
                    self.q.get_nowait()
                except Exception:
                    break
        if self.q.qsize() < 5:
            self.q.put(text)

    def ask_ollama_and_say(self, nickname, comment, current_title, title_a, title_b):
        now = time.time()
        if now - self.last_comment_llm < 7.0 or self.llm_q.qsize() >= 2:
            return
        self.last_comment_llm = now
        self.llm_q.put((nickname, comment, current_title, title_a, title_b))

    def generate_ai_bot_comment(self, bot_nick, current_title, title_a, title_b):
        if self.bot_comment_q.qsize() < 2:
            self.bot_comment_q.put((bot_nick, current_title, title_a, title_b))

    def _ollama_fake_comment_worker(self):
        temas = [
            "elogiando los redobles y la energía en la batería",
            "diciendo que esa canción le trae grandes recuerdos",
            "apoyando con entusiasmo que gane la canción de la opción A",
            "apoyando con entusiasmo que gane la canción de la opción B",
            "mandando saludos desde su ciudad y felicitando al baterista",
            "comentando lo bien que suena el ritmo y el bombo",
        ]
        while True:
            bot_nick, current_title, title_a, title_b = self.bot_comment_q.get()
            tema = random.choice(temas)
            prompt = (
                f"Actúa como un espectador joven y entusiasta en un stream donde están tocando "
                f"en batería la canción '{current_title}', y se está votando entre '{title_a}' (Opción A) "
                f"y '{title_b}' (Opción B). "
                f"Escribe ÚNICAMENTE un comentario corto de chat en español (máximo 10 palabras) {tema}. "
                f"No uses comillas ni explicaciones."
            )
            generated_comment = None
            try:
                resp = requests.post(
                    OLLAMA_URL,
                    json={
                        "model": OLLAMA_MODEL,
                        "prompt": prompt,
                        "stream": False,
                        "options": {
                            "temperature": 0.92,
                            "top_p": 0.95,
                            "num_predict": 28,
                        },
                    },
                    timeout=6,
                )
                if resp.status_code == 200:
                    raw = resp.json().get("response", "").strip()
                    raw = raw.replace('"', "").replace("'", "").split("\n")[0].strip()
                    if len(raw) >= 4:
                        generated_comment = raw
            except Exception as e:
                print(f"[Ollama Comment Aviso] {e}")

            if not generated_comment:
                generated_comment = f"¡Qué brutal suena {current_title} en la batería!"

            with state_lock:
                floating_texts.append({
                    "text": f"💬 @{bot_nick[:10]}: {generated_comment[:28]}",
                    "x": WIDTH // 2,
                    "y": HEIGHT * 0.52,
                    "vy": -0.9,
                    "life": 90,
                    "color": (255, 240, 180)
                })

            self.ask_ollama_and_say(bot_nick, generated_comment, current_title, title_a, title_b)

    def _ollama_reply_worker(self):
        while True:
            nickname, comment, current_title, title_a, title_b = self.llm_q.get()
            clean_nick = nickname[:14].replace("_", " ")
            prompt = (
                f"Eres el animador carismático del stream de batería de Julio (en TikTok, Twitch, YouTube y Facebook). "
                f"Actualmente suena '{current_title}'. "
                f"La votación para la siguiente canción es: Opción A '{title_a}' contra Opción B '{title_b}'. "
                f"El espectador '{clean_nick}' comentó en el chat: '{comment}'. "
                f"Responde en español de forma muy breve, natural y entusiasta (máximo 18 palabras), "
                f"saludándolo o contestando su mensaje e invitando a votar con A o B."
            )
            try:
                resp = requests.post(
                    OLLAMA_URL,
                    json={
                        "model": OLLAMA_MODEL,
                        "prompt": prompt,
                        "stream": False,
                        "options": {"temperature": 0.75, "num_predict": 45},
                    },
                    timeout=6,
                )
                if resp.status_code == 200:
                    ai_reply = resp.json().get("response", "").strip().replace('"', "")
                    if ai_reply:
                        self.say(f"{clean_nick} dice: {comment}. {ai_reply}")
                        continue
            except Exception as e:
                print(f"[Ollama Reply Aviso] {e}")

            self.say(f"{clean_nick} comenta: {comment}. ¡Gracias por apoyar el live!")

    def _play_audio_file(self, mp3_path):
        wav_path = mp3_path.replace(".mp3", ".wav")
        if self.has_ffmpeg and not os.path.exists(wav_path):
            subprocess.run(
                ["ffmpeg", "-y", "-i", mp3_path, "-ar", "44100", "-ac", "1", wav_path],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )

        if os.path.exists(wav_path) and self.has_pwplay:
            subprocess.run(["pw-play", "--volume=1.0", wav_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif os.path.exists(wav_path) and self.has_paplay:
            subprocess.run(["paplay", wav_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif self.has_ffplay:
            subprocess.run(
                ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", mp3_path],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        elif self.has_mpv:
            subprocess.run(["mpv", "--no-video", "--really-quiet", mp3_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def _tts_worker(self):
        while True:
            text = self.q.get()
            self.speaking = True
            self.current_subtitle = text
            try:
                chunks = [text[i:i + 180] for i in range(0, len(text), 180)]
                for chunk in chunks:
                    text_hash = hashlib.md5(chunk.encode("utf-8")).hexdigest()[:12]
                    mp3_path = os.path.join(TTS_DIR, f"tts_{text_hash}.mp3")

                    if not os.path.exists(mp3_path):
                        url = "https://translate.googleapis.com/translate_tts"
                        params = {"client": "gtx", "ie": "UTF-8", "tl": "es-MX", "dt": "t", "q": chunk}
                        headers = {"User-Agent": "Mozilla/5.0"}
                        resp = requests.get(url, params=params, headers=headers, timeout=5)
                        if resp.status_code == 200 and len(resp.content) > 400:
                            with open(mp3_path, "wb") as f:
                                f.write(resp.content)

                    if os.path.exists(mp3_path):
                        self._play_audio_file(mp3_path)
                    elif self.has_espeak:
                        subprocess.run([self.has_espeak, "-v", "es", chunk], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception as e:
                print(f"[TTS Aviso] {e}")
            finally:
                time.sleep(0.25)
                self.speaking = False
                self.current_subtitle = ""


# ================= MOTOR DE FUENTES CON SOMBRA =================
class HybridFont:
    def __init__(self, name, size, bold=True):
        self.use_pg = False
        try:
            self.pg_font = pygame.font.SysFont(name, size, bold=bold)
            self.use_pg = True
        except Exception:
            self.pil_font = self._load_pil_font(size)

    def _load_pil_font(self, size):
        candidates = [
            "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/TTF/LiberationSans-Bold.ttf",
            "/usr/share/fonts/noto/NotoSans-Bold.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        ]
        for path in candidates:
            if os.path.exists(path):
                try:
                    return ImageFont.truetype(path, size)
                except Exception:
                    pass
        return ImageFont.load_default()

    def render(self, text, color, shadow_color=(8, 8, 14), offset=2):
        if self.use_pg:
            fg = self.pg_font.render(text, True, color)
            if not shadow_color:
                return fg
            sh = self.pg_font.render(text, True, shadow_color)
            surf = pygame.Surface((fg.get_width() + offset * 2, fg.get_height() + offset * 2), pygame.SRCALPHA)
            surf.blit(sh, (offset * 2, offset * 2))
            surf.blit(fg, (0, 0))
            return surf

        bbox = self.pil_font.getbbox(text)
        w = max(1, bbox[2] - bbox[0] + 6)
        h = max(1, bbox[3] - bbox[1] + 6)
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        if shadow_color:
            draw.text((-bbox[0] + 2 + offset, -bbox[1] + 2 + offset), text, font=self.pil_font, fill=(*shadow_color, 230))
        draw.text((-bbox[0] + 2, -bbox[1] + 2), text, font=self.pil_font, fill=(*color, 255))
        return pygame.image.fromstring(img.tobytes(), img.size, img.mode)


# ================= SÍNTESIS DE SONIDOS ARCADE DE VIDEOJUEGO (.WAV) =================
def save_wav(filename, samples, sample_rate=44100):
    filepath = os.path.join(ASSETS_DIR, filename)
    if os.path.exists(filepath):
        return filepath
    with wave.open(filepath, "w") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        frames = bytearray()
        for s in samples:
            clipped = max(-1.0, min(1.0, s))
            frames.extend(struct.pack("<h", int(clipped * 32767)))
        wav_file.writeframes(frames)
    return filepath


def setup_assets():
    os.makedirs(ASSETS_DIR, exist_ok=True)
    sr = 44100

    if not os.path.exists(os.path.join(ASSETS_DIR, "arcade_vote_a.wav")):
        dur = 0.28
        notes = [523.25, 659.25, 783.99, 1046.50]
        samples = []
        for i in range(int(sr * dur)):
            t = i / sr
            idx = min(len(notes) - 1, int((t / dur) * len(notes)))
            f = notes[idx]
            sq = 0.35 if math.sin(2 * math.pi * f * t) >= 0 else -0.35
            sn = math.sin(2 * math.pi * f * t) * 0.55 + math.sin(4 * math.pi * f * t) * 0.2
            env = (1.0 - (t / dur)) ** 0.55
            samples.append((sq + sn) * env * 0.75)
        save_wav("arcade_vote_a.wav", samples, sr)

    if not os.path.exists(os.path.join(ASSETS_DIR, "arcade_vote_b.wav")):
        dur = 0.28
        notes = [587.33, 739.99, 880.00, 1174.66]
        samples = []
        for i in range(int(sr * dur)):
            t = i / sr
            idx = min(len(notes) - 1, int((t / dur) * len(notes)))
            f = notes[idx]
            sq = 0.35 if math.sin(2 * math.pi * f * t) >= 0 else -0.35
            sn = math.sin(2 * math.pi * f * t) * 0.55 + math.sin(3 * math.pi * f * t) * 0.2
            env = (1.0 - (t / dur)) ** 0.55
            samples.append((sq + sn) * env * 0.75)
        save_wav("arcade_vote_b.wav", samples, sr)

    if not os.path.exists(os.path.join(ASSETS_DIR, "arcade_combo.wav")):
        dur = 0.36
        samples = []
        for i in range(int(sr * dur)):
            t = i / sr
            chord = [523.25, 659.25, 783.99] if t < 0.14 else [659.25, 830.61, 987.77, 1318.5]
            val = sum(math.sin(2 * math.pi * f * t) for f in chord) / len(chord)
            sq = 0.25 if math.sin(2 * math.pi * chord[-1] * t) >= 0 else -0.25
            env = (1.0 - (t / dur)) ** 0.5
            samples.append((val * 0.7 + sq) * env * 0.8)
        save_wav("arcade_combo.wav", samples, sr)

    if not os.path.exists(os.path.join(ASSETS_DIR, "arcade_laser.wav")):
        dur = 0.12
        samples = []
        for i in range(int(sr * dur)):
            t = i / sr
            freq = 920 * math.exp(-t * 28) + 120
            env = (1.0 - t / dur) ** 1.5
            sq = 0.3 if math.sin(2 * math.pi * freq * t) >= 0 else -0.3
            samples.append((math.sin(2 * math.pi * freq * t) * 0.6 + sq) * env * 0.55)
        save_wav("arcade_laser.wav", samples, sr)

    if not os.path.exists(os.path.join(ASSETS_DIR, "arcade_powerup.wav")):
        dur = 0.9
        samples = []
        notes = [329.63, 392.00, 523.25, 659.25, 783.99, 1046.50]
        for i in range(int(sr * dur)):
            t = i / sr
            idx = min(len(notes) - 1, int((t / dur) * len(notes)))
            freq = notes[idx]
            sub = math.sin(2 * math.pi * (110 * math.exp(-t * 1.6)) * t) * 0.45
            lead = math.sin(2 * math.pi * freq * t) + 0.4 * math.sin(4 * math.pi * freq * t)
            env = min(1.0, t * 35) * ((1.0 - t / dur) ** 0.7)
            samples.append((lead * 0.45 + sub) * env * 0.85)
        save_wav("arcade_powerup.wav", samples, sr)

    if not os.path.exists(os.path.join(ASSETS_DIR, "arcade_victory.wav")):
        dur = 1.5
        samples = []
        chord = [523.25, 659.25, 783.99, 1046.50]
        for i in range(int(sr * dur)):
            t = i / sr
            env = (1.0 - t / dur) ** 0.6
            val = sum(math.sin(2 * math.pi * f * t) for f in chord) / len(chord)
            samples.append(val * env * 0.8)
        save_wav("arcade_victory.wav", samples, sr)


# ================= ESTADO GLOBAL DEL JUEGO Y VOTACIÓN =================
players = {}
projectiles = []
shockwaves = []
floating_texts = []
rose_bursts = []
fire_particles = []

score_a = 1000
score_b = 1000
use_chroma = False
tiktok_connected = False
twitch_connected = False
youtube_connected = False
facebook_connected = False
round_banner_timer = 0
round_winner_text = ""

copyright_skip_triggered = False
copyright_skip_reason = ""
last_copyright_trigger_time = 0.0

displayed_viewers = random.randint(35, 48)
real_tiktok_viewers = 0
stream_start_time = time.time()
last_real_interaction = 0.0
real_interactions_count = 0
combo_counter = 0
last_vote_time = 0.0

video_library = []
current_song = None
option_a_song = None
option_b_song = None

state_lock = threading.Lock()
sounds = {}
narrator = None


def trigger_copyright_protection(reason="Alerta de Copyright"):
    """Activa el bloqueo inmediato de la canción actual y solicita saltar a la siguiente."""
    global copyright_skip_triggered, copyright_skip_reason, last_copyright_trigger_time
    now = time.time()
    if now - last_copyright_trigger_time < 5.0:
        return
    last_copyright_trigger_time = now
    copyright_skip_reason = reason
    copyright_skip_triggered = True


# ================= AVATARES PROCEDURALES =================
def generate_gamer_avatar(nickname, size=140, platform="TT"):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    h = int(hashlib.md5(nickname.encode("utf-8")).hexdigest()[:6], 16)
    if platform == "TW":
        c1 = (95 + (h & 0x3F), 35 + ((h >> 7) & 0x3F), 165 + ((h >> 14) & 0x4F))
    elif platform == "YT":
        c1 = (165 + (h & 0x4F), 25 + ((h >> 7) & 0x2F), 35 + ((h >> 14) & 0x2F))
    elif platform == "FB":
        c1 = (20 + (h & 0x2F), 85 + ((h >> 7) & 0x4F), 195 + ((h >> 14) & 0x3F))
    else:
        c1 = (60 + (h & 0x7F), 40 + ((h >> 7) & 0x7F), 90 + ((h >> 14) & 0x7F))
    c2 = (min(255, c1[0] + 75), min(255, c1[1] + 55), min(255, c1[2] + 75))

    draw.ellipse((0, 0, size - 1, size - 1), fill=(*c1, 255))
    draw.ellipse((12, 12, size - 13, size - 13), fill=(*c2, 210))
    draw.ellipse((26, 26, size - 27, size - 27), fill=(*c1, 240))

    return pygame.image.fromstring(img.tobytes(), img.size, img.mode)


# ================= EFECTO DE FUEGO ALTO Y ASCENDENTE =================
def init_high_fire(count=65):
    fire_particles.clear()
    for _ in range(count):
        fire_particles.append(_make_ember(random_y=True))


def _make_ember(random_y=False):
    return {
        "x": random.uniform(12, WIDTH - 12),
        "y": random.uniform(HEIGHT * 0.14, HEIGHT) if random_y else HEIGHT + random.uniform(2, 25),
        "vx": random.uniform(-0.55, 0.55),
        "vy": random.uniform(-1.65, -3.75),
        "size": random.uniform(4.0, 9.5),
        "alpha": random.randint(140, 235),
        "fade": random.uniform(0.22, 0.44),
        "phase": random.uniform(0, 6.28),
        "color": random.choice([
            (255, 65, 15),
            (255, 110, 25),
            (255, 160, 40),
            (255, 205, 75),
            (255, 235, 130),
        ])
    }


def update_and_draw_high_fire(surface, t_sec):
    ember_layer = pygame.Surface((WIDTH, HEIGHT), pygame.SRCALPHA)

    flick = int(math.sin(t_sec * 9.0) * 12)
    pygame.draw.ellipse(ember_layer, (255, 50, 10, 28), (-60, HEIGHT - 150 + flick, WIDTH + 120, 210))
    pygame.draw.ellipse(ember_layer, (255, 115, 20, 38), (-30, HEIGHT - 95 - flick // 2, WIDTH + 60, 135))

    for fp in fire_particles:
        swirl = math.sin(t_sec * 3.2 + fp["phase"] + fp["y"] * 0.012) * 0.65
        fp["x"] += fp["vx"] + swirl
        fp["y"] += fp["vy"]
        fp["alpha"] = max(0.0, fp["alpha"] - fp["fade"])
        fp["size"] = max(1.2, fp["size"] - 0.016)

        if fp["y"] < HEIGHT * 0.12 or fp["alpha"] <= 12:
            fp.update(_make_ember(random_y=False))

        r = int(fp["size"])
        x_int, y_int = int(fp["x"]), int(fp["y"])
        alpha_int = int(fp["alpha"])

        flame_h = int(r * 2.4)
        pygame.draw.ellipse(
            ember_layer,
            (*fp["color"], max(10, alpha_int // 2)),
            (x_int - r, y_int - r, r * 2, flame_h)
        )
        pygame.draw.circle(ember_layer, (*fp["color"], alpha_int), (x_int, y_int), r)
        if r >= 3:
            pygame.draw.circle(
                ember_layer,
                (255, 250, 200, int(alpha_int * 0.75)),
                (x_int, y_int),
                max(1, r // 2)
            )

    surface.blit(ember_layer, (0, 0))


# ================= SELECCIÓN DE CANCIONES Y RONDAS =================
def pick_two_candidates(exclude_paths):
    pool = [v for v in video_library if v["path"] not in exclude_paths]
    if len(pool) < 2:
        pool = list(video_library)
    if len(pool) >= 2:
        return random.sample(pool, 2)
    elif len(pool) == 1:
        return [pool[0], pool[0]]
    return [
        {"title": "Canción A", "path": "", "filename": ""},
        {"title": "Canción B", "path": "", "filename": ""},
    ]


def announce_current_vote(priority=False):
    if not narrator or not option_a_song or not option_b_song:
        return
    msg = (
        f"¡Bienvenidos al Live! Vota por la siguiente canción: "
        f"Comenta A para {option_a_song['title']}, "
        f"o comenta B para {option_b_song['title']}."
    )
    narrator.say(msg, priority=priority)


# ================= DESCARGA DE AVATARES =================
def create_circular_avatar(url, size):
    try:
        resp = requests.get(url, timeout=3)
        img = Image.open(io.BytesIO(resp.content)).convert("RGBA")
        img = img.resize((size, size), Image.Resampling.LANCZOS)
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, size, size), fill=255)
        output = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        output.paste(img, (0, 0), mask)
        return pygame.image.fromstring(output.tobytes(), output.size, output.mode)
    except Exception:
        return None


def fetch_avatar_async(user_id, url):
    surf = create_circular_avatar(url, 140)
    if surf:
        with state_lock:
            if user_id in players:
                players[user_id]["base_avatar"] = surf


# ================= LÓGICA DE JUGADORES, COMBOS Y CONTROL DE BURBUJAS =================
def _enforce_bubble_limit():
    if len(players) <= MAX_BUBBLES_ON_SCREEN:
        return
    sorted_uids = sorted(
        players.keys(),
        key=lambda k: (0 if players[k].get("is_bot") else 1, players[k].get("last_active", 0))
    )
    while len(players) > MAX_BUBBLES_ON_SCREEN and sorted_uids:
        oldest_uid = sorted_uids.pop(0)
        players.pop(oldest_uid, None)


def join_team(user_id, nickname, team, avatar_url=None, announce_tts=True, is_bot=False, platform="TT"):
    global score_a, score_b, combo_counter, last_vote_time
    now = time.time()

    with state_lock:
        anchor = ANCHOR_A if team == "A" else ANCHOR_B
        color = COLOR_DEMON_GLOW if team == "A" else COLOR_ANGEL_GLOW
        song_choice = option_a_song["title"] if (team == "A" and option_a_song) else (option_b_song["title"] if option_b_song else team)

        if now - last_vote_time < 3.2:
            combo_counter += 1
        else:
            combo_counter = 1
        last_vote_time = now

        if combo_counter >= 3 and "combo" in sounds:
            sounds["combo"].play()
        elif team == "A" and "vote_a" in sounds:
            sounds["vote_a"].play()
        elif "vote_b" in sounds:
            sounds["vote_b"].play()

        if user_id not in players:
            _enforce_bubble_limit()
            angle = random.uniform(0, 2 * math.pi)
            dist = random.uniform(20, 85)
            players[user_id] = {
                "uid": user_id,
                "nickname": nickname[:16],
                "team": team,
                "platform": platform,
                "is_bot": is_bot,
                "last_active": now,
                "participated_this_song": True,
                "x": anchor[0] + math.cos(angle) * dist,
                "y": anchor[1] + math.sin(angle) * dist,
                "vx": 0.0,
                "vy": 0.0,
                "radius": 5.0,
                "target_radius": 20.0,
                "radius_vel": 7.5,
                "power": 25,
                "flowers": 0,
                "base_avatar": generate_gamer_avatar(nickname, 140, platform),
                "pulse": 16,
                "float_phase": random.uniform(0, 6.28),
                "float_speed": random.uniform(2.0, 3.4),
                "float_amp": random.uniform(5.0, 9.5),
                "orbit_dir": random.choice([-1, 1]),
                "seed_color": (
                    random.randint(60, 140),
                    random.randint(60, 140),
                    random.randint(80, 160)
                )
            }

            if avatar_url and not is_bot:
                threading.Thread(target=fetch_avatar_async, args=(user_id, avatar_url), daemon=True).start()
        else:
            players[user_id]["team"] = team
            players[user_id]["pulse"] = 16
            players[user_id]["radius_vel"] = 6.0
            players[user_id]["last_active"] = now
            players[user_id]["participated_this_song"] = True

        if platform == "TW":
            plat_icon = "🟣"
            txt_col = COLOR_TWITCH
        elif platform == "YT":
            plat_icon = "▶️"
            txt_col = COLOR_YOUTUBE
        elif platform == "FB":
            plat_icon = "🔵"
            txt_col = COLOR_FACEBOOK
        else:
            plat_icon = "🎮"
            txt_col = COLOR_GOLD if combo_counter >= 3 else color

        combo_str = f" 🔥COMBO x{combo_counter}!" if combo_counter >= 2 else " +50 PTS!"
        floating_texts.append({
            "text": f"{plat_icon} @{nickname[:11]} VOTA {team}!{combo_str}",
            "x": anchor[0] + random.uniform(-25, 25),
            "y": anchor[1] - 105,
            "vy": -1.45,
            "life": 60,
            "color": txt_col
        })

        for _ in range(10):
            ang = random.uniform(0, 2 * math.pi)
            spd = random.uniform(2.0, 5.5)
            rose_bursts.append({
                "x": players[user_id]["x"],
                "y": players[user_id]["y"],
                "vx": math.cos(ang) * spd,
                "vy": math.sin(ang) * spd,
                "size": random.randint(4, 8),
                "life": random.randint(18, 32),
                "color": random.choice([color, COLOR_GOLD, txt_col])
            })

        if announce_tts and narrator and (now - narrator.last_join_tts > 7.5):
            narrator.last_join_tts = now
            clean_nick = nickname[:12].replace("_", " ")
            origen_map = {"TW": "desde Twitch", "YT": "desde YouTube", "FB": "desde Facebook"}
            origen = origen_map.get(platform, "")
            narrator.say(f"¡{clean_nick} {origen} vota por {song_choice}!")

    trigger_attack(user_id, multiplier=2, is_flower=False)


def trigger_attack(user_id, multiplier=1, is_flower=False):
    global score_a, score_b
    with state_lock:
        if user_id not in players:
            return
        p = players[user_id]
        p["pulse"] = 18
        p["last_active"] = time.time()
        p["participated_this_song"] = True

        if is_flower:
            p["flowers"] += multiplier
            p["target_radius"] = min(60.0, p["target_radius"] + 8.5 * multiplier)
            p["radius_vel"] = 9.0
            p["power"] += 60 * multiplier

            if "powerup" in sounds:
                sounds["powerup"].play()

            shockwaves.append({
                "x": p["x"],
                "y": p["y"],
                "r": p["radius"],
                "max_r": 195,
                "color": COLOR_GOLD if p["flowers"] >= 2 else COLOR_ROSE,
                "text": f"@{p['nickname']} SUPER VOTO 🌹x{p['flowers']}"
            })

            for _ in range(16):
                ang = random.uniform(0, 2 * math.pi)
                spd = random.uniform(2.5, 7.0)
                rose_bursts.append({
                    "x": p["x"],
                    "y": p["y"],
                    "vx": math.cos(ang) * spd,
                    "vy": math.sin(ang) * spd,
                    "size": random.randint(5, 10),
                    "life": random.randint(25, 45),
                    "color": random.choice([COLOR_ROSE, COLOR_GOLD, (255, 140, 60)])
                })

            if narrator:
                clean_nick = p["nickname"][:12].replace("_", " ")
                song_name = option_a_song["title"] if (p["team"] == "A" and option_a_song) else (option_b_song["title"] if option_b_song else p["team"])
                narrator.say(f"¡Increíble! {clean_nick} activó el Super Voto para impulsar {song_name}!")
        else:
            p["radius_vel"] = max(p["radius_vel"], 2.8)
            if "laser" in sounds:
                sounds["laser"].play()

        dmg = p["power"] * multiplier
        target = ANCHOR_B if p["team"] == "A" else ANCHOR_A

        if p["team"] == "A":
            score_a += dmg
        else:
            score_b += dmg

        num_proj = min(10, max(1, multiplier * (4 if is_flower else 1)))
        for _ in range(num_proj):
            projectiles.append({
                "x": p["x"] + random.uniform(-10, 10),
                "y": p["y"] + random.uniform(-10, 10),
                "tx": target[0] + random.uniform(-45, 45),
                "ty": target[1] + random.uniform(-45, 45),
                "color": COLOR_GOLD if is_flower else (COLOR_DEMON_GLOW if p["team"] == "A" else COLOR_ANGEL_GLOW),
                "size": 8 if is_flower else 4
            })


# ================= GESTOR DE ACTIVIDAD AUTOMÁTICA =================
class BotActivityManager:
    def __init__(self):
        self.next_bot_vote = time.time() + 3.0
        self.next_bot_tap = time.time() + 1.5
        self.next_viewer_tick = time.time() + 2.5

    def update(self):
        global displayed_viewers
        now = time.time()

        if now >= self.next_viewer_tick:
            self.next_viewer_tick = now + random.uniform(2.5, 4.5)
            delta = random.choice([-2, -1, 0, 1, 1, 2, 3])
            base_v = max(MIN_VIEWERS_DISPLAY, min(78, displayed_viewers + delta))
            displayed_viewers = max(MIN_VIEWERS_DISPLAY, base_v + real_tiktok_viewers)

        if not ENABLE_BOTS:
            return

        elapsed_minutes = (now - stream_start_time) / 60.0
        time_since_real = now - last_real_interaction

        low_interaction = (elapsed_minutes <= BOT_SIMULATION_MINUTES and real_interactions_count < 15) or (time_since_real > 6.5)

        if not low_interaction:
            return

        if now >= self.next_bot_vote:
            self.next_bot_vote = now + random.uniform(2.8, 6.0)
            bot_nick = random.choice(FAKE_USERS_POOL)
            bot_uid = f"user_{bot_nick}"

            if abs(score_a - score_b) > 700:
                team = "A" if score_a < score_b else "B"
            else:
                team = random.choice(["A", "B"])

            announce = random.random() < 0.30
            fake_plat = random.choice(["TT", "TW", "YT", "FB"])
            join_team(bot_uid, bot_nick, team, avatar_url=None, announce_tts=announce, is_bot=True, platform=fake_plat)

            if random.random() < 0.18 and narrator and option_a_song and option_b_song and current_song:
                comment_bot = random.choice(FAKE_USERS_POOL)
                narrator.generate_ai_bot_comment(
                    comment_bot,
                    current_song["title"],
                    option_a_song["title"],
                    option_b_song["title"],
                )

        if now >= self.next_bot_tap and players:
            self.next_bot_tap = now + random.uniform(1.1, 2.4)
            random_uid = random.choice(list(players.keys()))
            is_rose = random.random() < 0.06
            trigger_attack(random_uid, multiplier=1 if is_rose else random.randint(1, 3), is_flower=is_rose)


# ================= PROCESADOR UNIFICADO DE MENSAJES EXTERNOS =================
def _process_incoming_external_message(uid, nick, raw_msg, platform="FB", avatar_url=None, is_super=False):
    register_real_interaction()

    if es_alerta_copyright_chat(raw_msg):
        trigger_copyright_protection(f"Alerta en {platform} por @{nick[:10]}")
        return

    if is_super:
        if uid not in players:
            team = "A" if score_a <= score_b else "B"
            join_team(uid, nick, team, avatar_url=avatar_url, announce_tts=False, is_bot=False, platform=platform)
        trigger_attack(uid, multiplier=3, is_flower=True)
        return

    if not raw_msg:
        return

    voto = detectar_voto(raw_msg)
    if voto == "A":
        join_team(uid, nick, "A", avatar_url=avatar_url, announce_tts=True, is_bot=False, platform=platform)
    elif voto == "B":
        join_team(uid, nick, "B", avatar_url=avatar_url, announce_tts=True, is_bot=False, platform=platform)
    elif raw_msg.lower() in ("tap", "!tap", "atacar", "!atacar", "gg", "fuego"):
        if uid not in players:
            team = "A" if score_a <= score_b else "B"
            join_team(uid, nick, team, avatar_url=avatar_url, announce_tts=False, is_bot=False, platform=platform)
        trigger_attack(uid, multiplier=4, is_flower=False)
    else:
        icon = "🔵" if platform == "FB" else "▶️"
        col = COLOR_FACEBOOK if platform == "FB" else COLOR_YOUTUBE
        with state_lock:
            if uid in players:
                players[uid]["last_active"] = time.time()
                players[uid]["participated_this_song"] = True
            floating_texts.append({
                "text": f"{icon} @{nick[:10]}: {raw_msg[:26]}",
                "x": WIDTH // 2,
                "y": HEIGHT * 0.52,
                "vy": -0.9,
                "life": 85,
                "color": col
            })
        if narrator and len(raw_msg) >= 2:
            cur_t = current_song["title"] if current_song else "Cover de Batería"
            ta = option_a_song["title"] if option_a_song else "Opción A"
            tb = option_b_song["title"] if option_b_song else "Opción B"
            narrator.ask_ollama_and_say(nick, raw_msg, cur_t, ta, tb)


# ================= CLIENTE FACEBOOK LIVE (theJulius555) + DETECTOR COPYRIGHT =================
def start_facebook_thread():
    global facebook_connected, displayed_viewers
    fb_live_url = FACEBOOK_PAGE_URL.rstrip("/") + "/live"
    session = requests.Session()
    session.headers.update({
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
        "Accept-Language": "es-MX,es;q=0.9,en;q=0.8",
    })

    seen_fb_comments = set()
    seen_fb_users = set()

    while True:
        try:
            resp = session.get(fb_live_url, timeout=10)
            html = resp.text

            is_live = (
                '"is_live_streaming":true' in html
                or '"is_live":true' in html
                or '"broadcast_status":"LIVE"' in html
            )

            if not is_live:
                facebook_connected = False
                time.sleep(22)
                continue

            facebook_connected = True
            print(f"[Facebook LIVE] 🔵 ¡Transmisión en vivo detectada en {FACEBOOK_PAGE_URL}!")

            first_batch = True
            while True:
                r_poll = session.get(fb_live_url, timeout=10)
                if r_poll.status_code != 200:
                    break
                page_txt = r_poll.text

                if (
                    '"is_audio_muted":true' in page_txt
                    or '"audio_muted":true' in page_txt
                    or '"copyright_violation"' in page_txt
                ):
                    trigger_copyright_protection("Facebook silenció audio por Copyright")

                if (
                    '"is_live_streaming":true' not in page_txt
                    and '"is_live":true' not in page_txt
                    and '"broadcast_status":"LIVE"' not in page_txt
                ):
                    break

                matches = re.findall(
                    r'"author"\s*:\s*\{[^}]*?"name"\s*:\s*"([^"]+)"[^}]*?\}.*?"body"\s*:\s*\{"text"\s*:\s*"([^"]+)"\}',
                    page_txt
                )

                for raw_author, raw_text in matches:
                    try:
                        nick = bytes(raw_author, "utf-8").decode("unicode_escape")
                    except Exception:
                        nick = raw_author
                    try:
                        msg = bytes(raw_text, "utf-8").decode("unicode_escape").strip()
                    except Exception:
                        msg = raw_text.strip()

                    cid = hashlib.md5(f"{nick}:{msg}".encode("utf-8")).hexdigest()[:16]
                    if cid in seen_fb_comments:
                        continue
                    seen_fb_comments.add(cid)

                    if first_batch:
                        continue

                    print(f"[Facebook Chat] 🔵 @{nick}: {msg}")

                    uid = f"fb_{nick.lower()}"
                    if uid not in seen_fb_users:
                        seen_fb_users.add(uid)
                        displayed_viewers = max(MIN_VIEWERS_DISPLAY, displayed_viewers + 1)
                        if narrator and (time.time() - narrator.last_join_tts > 8.5):
                            narrator.last_join_tts = time.time()
                            clean_nick = nick[:14].replace("_", " ")
                            narrator.say(f"¡Bienvenido {clean_nick} desde Facebook Live! Comenta A o B para votar.")

                    _process_incoming_external_message(uid, nick, msg, platform="FB")

                first_batch = False
                time.sleep(3.0)

        except Exception as e:
            print(f"[Facebook Live Aviso] {e}")
        finally:
            facebook_connected = False
            time.sleep(20)


# ================= CLIENTE YOUTUBE LIVE (@rasec555) EN MODO "TODOS LOS MENSAJES" =================
def _extract_yt_continuation(chat_cont):
    """Extrae el siguiente token de continuación del JSON de YouTube Live Chat."""
    for c in chat_cont.get("continuations", []):
        for key in (
            "invalidationContinuationData",
            "timedContinuationData",
            "reloadContinuationData",
            "liveChatReplayContinuationData",
        ):
            if key in c and "continuation" in c[key]:
                return c[key]["continuation"]
    return None


def _check_youtube_copyright_status(html_or_json_str):
    patrones_copy = [
        r'"status"\s*:\s*"(?:ERROR|UNPLAYABLE|LIVE_STREAM_OFFLINE)"[^}]*?"reason"\s*:\s*"[^"]*?(?:copyright|derechos de autor|SME|UMG|WMG| Warner | Sony | Universal |blocked)[^"]*?"',
        r"contenido protegido por derechos de autor",
        r"bloqueó este video por motivos de derechos de autor",
        r"audio muted due to a copyright claim",
        r"se silenció el audio debido a un reclamo por derechos de autor",
    ]
    for pat in patrones_copy:
        if re.search(pat, html_or_json_str, flags=re.IGNORECASE):
            return True
    return False


def _get_youtube_live_chat_session(session, channel_url):
    """
    1. Entra a @rasec555/live y verifica que haya directo activo.
    2. Obtiene el videoId del directo y abre /live_chat?v=VIDEO_ID.
    3. Selecciona el token de 'Chat en vivo (Todos los mensajes)' para que YouTube NO filtre 'a' y 'b'.
    """
    live_url = channel_url.rstrip("/") + "/live"
    resp = session.get(live_url, timeout=10)
    html = resp.text

    if _check_youtube_copyright_status(html):
        trigger_copyright_protection("YouTube detectó reclamo de Copyright")

    if '"isLive":true' not in html and '"isLiveNow":true' not in html and '"liveChatRenderer"' not in html:
        return None, None, None

    vid_match = (
        re.search(r'"videoDetails"\s*:\s*\{[^}]*?"videoId"\s*:\s*"([a-zA-Z0-9_-]{11})"', html)
        or re.search(r'rel="canonical"\s+href="https://www\.youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})"', html)
        or re.search(r'"videoId"\s*:\s*"([a-zA-Z0-9_-]{11})"', html)
    )
    if not vid_match:
        return None, None, None

    video_id = vid_match.group(1)

    chat_page_url = f"https://www.youtube.com/live_chat?v={video_id}"
    r_chat_page = session.get(chat_page_url, timeout=10)
    chat_html = r_chat_page.text

    api_key_match = re.search(r'"INNERTUBE_API_KEY"\s*:\s*"([^"]+)"', chat_html)
    if not api_key_match:
        return None, None, None
    api_key = api_key_match.group(1)

    all_reload_tokens = re.findall(
        r'"reloadContinuationData"\s*:\s*\{\s*"continuation"\s*:\s*"([^"]+)"',
        chat_html,
    )

    if len(all_reload_tokens) >= 2:
        # El segundo token corresponde a "Chat en vivo" (Todos los mensajes sin filtro de spam)
        continuation = all_reload_tokens[1]
    elif all_reload_tokens:
        continuation = all_reload_tokens[0]
    else:
        cont_match = re.search(r'"continuation"\s*:\s*"([^"]+)"', chat_html)
        continuation = cont_match.group(1) if cont_match else None

    return video_id, api_key, continuation


def start_youtube_thread():
    global youtube_connected, displayed_viewers
    session = requests.Session()
    session.headers.update({
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
        "Accept-Language": "es-MX,es;q=0.9,en;q=0.8",
        "Referer": "https://www.youtube.com/",
    })
    session.cookies.set("CONSENT", "YES+cb", domain=".youtube.com")

    seen_yt_messages = set()
    seen_yt_users = set()

    while True:
        try:
            video_id, api_key, continuation = _get_youtube_live_chat_session(session, YOUTUBE_CHANNEL_URL)

            if not api_key or not continuation:
                if youtube_connected:
                    print("[YouTube LIVE] Directo finalizado o en espera de transmisión.")
                youtube_connected = False
                time.sleep(15)
                continue

            youtube_connected = True
            print(f"[YouTube LIVE] ▶️ ¡Conectado al chat en vivo de @rasec555 (Video ID: {video_id}) en modo TODOS LOS MENSAJES!")

            first_poll = True
            poll_counter = 0

            while continuation:
                poll_counter += 1
                if poll_counter % 10 == 0:
                    try:
                        r_watch = session.get(f"https://www.youtube.com/watch?v={video_id}", timeout=6)
                        if _check_youtube_copyright_status(r_watch.text):
                            trigger_copyright_protection("YouTube reportó reclamo de Copyright")
                    except Exception:
                        pass

                chat_url = f"https://www.youtube.com/youtubei/v1/live_chat/get_live_chat?key={api_key}"
                payload = {
                    "context": {
                        "client": {
                            "clientName": "WEB",
                            "clientVersion": "2.20240726.00.00",
                            "hl": "es",
                            "gl": "MX",
                        }
                    },
                    "continuation": continuation,
                }

                r_chat = session.post(chat_url, json=payload, timeout=10)
                if r_chat.status_code != 200:
                    break

                raw_json_txt = r_chat.text
                if _check_youtube_copyright_status(raw_json_txt):
                    trigger_copyright_protection("Alerta de Copyright en YouTube Live")

                data = r_chat.json()
                chat_cont = data.get("continuationContents", {}).get("liveChatContinuation", {})
                if not chat_cont:
                    break

                continuation = _extract_yt_continuation(chat_cont)
                actions = chat_cont.get("actions", [])

                for act in actions:
                    item = act.get("addChatItemAction", {}).get("item", {})
                    renderer = (
                        item.get("liveChatTextMessageRenderer")
                        or item.get("liveChatPaidMessageRenderer")
                    )
                    if not renderer:
                        continue

                    msg_id = renderer.get("id")
                    if not msg_id or msg_id in seen_yt_messages:
                        continue
                    seen_yt_messages.add(msg_id)

                    if first_poll:
                        continue

                    nick = renderer.get("authorName", {}).get("simpleText", "YouTuber")
                    channel_id = renderer.get("authorExternalChannelId") or nick
                    uid = f"yt_{channel_id}"

                    thumbs = renderer.get("authorPhoto", {}).get("thumbnails", [])
                    avatar_url = thumbs[-1].get("url") if thumbs else None

                    runs = renderer.get("message", {}).get("runs", [])
                    msg_parts = []
                    for run in runs:
                        if "text" in run:
                            msg_parts.append(run["text"])
                        elif "emoji" in run:
                            shortcuts = run["emoji"].get("shortcuts", [""])
                            msg_parts.append(shortcuts[0] if shortcuts else "")
                    raw_msg = "".join(msg_parts).strip()
                    is_superchat = "liveChatPaidMessageRenderer" in item

                    print(f"[YouTube Chat] ▶️ @{nick}: {raw_msg}")

                    if uid not in seen_yt_users:
                        seen_yt_users.add(uid)
                        displayed_viewers = max(MIN_VIEWERS_DISPLAY, displayed_viewers + 1)
                        if narrator and (time.time() - narrator.last_join_tts > 8.5):
                            narrator.last_join_tts = time.time()
                            clean_nick = nick[:14].replace("_", " ")
                            narrator.say(f"¡Bienvenido {clean_nick} desde YouTube! Comenta A o B para votar.")

                    _process_incoming_external_message(
                        uid, nick, raw_msg, platform="YT", avatar_url=avatar_url, is_super=is_superchat
                    )

                first_poll = False
                time.sleep(1.5)

        except Exception as e:
            print(f"[YouTube Live Aviso] {e}")
        finally:
            youtube_connected = False
            time.sleep(10)


# ================= CLIENTE TWITCH CHAT (bardack21) =================
def start_twitch_thread():
    global twitch_connected, displayed_viewers
    channel = TWITCH_CHANNEL.lower().strip().lstrip("@#")
    seen_twitch_users = set()

    while True:
        sock = None
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(240)
            sock.connect(("irc.chat.twitch.tv", 6667))

            sock.sendall(b"CAP REQ :twitch.tv/tags twitch.tv/commands\r\n")
            sock.sendall(b"PASS SCHMOOPIIE\r\n")
            anon_nick = f"justinfan{random.randint(10000, 99999)}"
            sock.sendall(f"NICK {anon_nick}\r\n".encode("utf-8"))
            sock.sendall(f"JOIN #{channel}\r\n".encode("utf-8"))

            buffer = ""
            while True:
                data = sock.recv(4096).decode("utf-8", errors="ignore")
                if not data:
                    break
                buffer += data
                lines = buffer.split("\r\n")
                buffer = lines.pop()

                for line in lines:
                    if not line:
                        continue

                    if line.startswith("PING"):
                        sock.sendall(b"PONG :tmi.twitch.tv\r\n")
                        continue

                    if f"JOIN #{channel}" in line or " 366 " in line:
                        if not twitch_connected:
                            twitch_connected = True
                            print(f"[Twitch LIVE] 🟣 ¡Conectado en tiempo real al canal #{channel}!")

                    if "PRIVMSG" in line:
                        register_real_interaction()
                        tags = {}
                        rest = line
                        if rest.startswith("@"):
                            tag_part, rest = rest.split(" ", 1)
                            for item in tag_part[1:].split(";"):
                                if "=" in item:
                                    k, v = item.split("=", 1)
                                    tags[k] = v

                        prefix, msg_part = rest.split("PRIVMSG", 1)
                        raw_msg = msg_part.split(" :", 1)[1].strip() if " :" in msg_part else ""
                        fallback_user = prefix.split("!")[0].lstrip(":") if "!" in prefix else "TwitchUser"
                        nick = tags.get("display-name") or fallback_user
                        uid = f"tw_{fallback_user.lower()}"

                        print(f"[Twitch Chat] 🟣 @{nick}: {raw_msg}")

                        if es_alerta_copyright_chat(raw_msg):
                            trigger_copyright_protection(f"Alerta en Twitch por @{nick[:10]}")
                            continue

                        if uid not in seen_twitch_users:
                            seen_twitch_users.add(uid)
                            displayed_viewers = max(MIN_VIEWERS_DISPLAY, displayed_viewers + 1)
                            if tags.get("first-msg") == "1" and narrator:
                                clean_nick = nick[:14].replace("_", " ")
                                narrator.say(f"¡Bienvenido {clean_nick} desde Twitch! Comenta A o B para votar.")

                        bits = int(tags.get("bits", "0") or 0)
                        if bits > 0:
                            if uid not in players:
                                team = "A" if score_a <= score_b else "B"
                                join_team(uid, nick, team, announce_tts=False, is_bot=False, platform="TW")
                            trigger_attack(uid, multiplier=max(1, bits // 10), is_flower=True)
                            continue

                        voto = detectar_voto(raw_msg)
                        if voto == "A":
                            join_team(uid, nick, "A", announce_tts=True, is_bot=False, platform="TW")
                        elif voto == "B":
                            join_team(uid, nick, "B", announce_tts=True, is_bot=False, platform="TW")
                        elif raw_msg.lower() in ("tap", "!tap", "atacar", "!atacar", "gg", "fuego"):
                            if uid not in players:
                                team = "A" if score_a <= score_b else "B"
                                join_team(uid, nick, team, announce_tts=False, is_bot=False, platform="TW")
                            trigger_attack(uid, multiplier=4, is_flower=False)
                        else:
                            with state_lock:
                                if uid in players:
                                    players[uid]["last_active"] = time.time()
                                    players[uid]["participated_this_song"] = True
                                floating_texts.append({
                                    "text": f"🟣 @{nick[:10]}: {raw_msg[:26]}",
                                    "x": WIDTH // 2,
                                    "y": HEIGHT * 0.52,
                                    "vy": -0.9,
                                    "life": 85,
                                    "color": COLOR_TWITCH
                                })
                            if narrator and len(raw_msg) >= 2:
                                cur_t = current_song["title"] if current_song else "Cover de Batería"
                                ta = option_a_song["title"] if option_a_song else "Opción A"
                                tb = option_b_song["title"] if option_b_song else "Opción B"
                                narrator.ask_ollama_and_say(nick, raw_msg, cur_t, ta, tb)

        except Exception as e:
            print(f"[Twitch Reintentando] {e}")
        finally:
            twitch_connected = False
            if sock:
                try:
                    sock.close()
                except Exception:
                    pass
            time.sleep(5)


# ================= CLIENTE TIKTOK LIVE =================
def extract_avatar_url(user):
    try:
        urls = getattr(user.avatar_thumb, "m_urls", None) or getattr(user.avatar_thumb, "url_list", None)
        return urls[0] if urls else None
    except Exception:
        return None


def register_real_interaction():
    global last_real_interaction, real_interactions_count
    last_real_interaction = time.time()
    real_interactions_count += 1


def start_tiktok_thread():
    global tiktok_connected
    while True:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        client = TikTokLiveClient(unique_id=TIKTOK_USERNAME)

        @client.on(ConnectEvent)
        async def on_connect(event: ConnectEvent):
            global tiktok_connected
            tiktok_connected = True
            print(f"[TikTok LIVE] 🔴 ¡Conectado en tiempo real a @{event.unique_id}!")
            announce_current_vote(priority=True)

        @client.on(DisconnectEvent)
        async def on_disconnect(event: DisconnectEvent):
            global tiktok_connected
            tiktok_connected = False

        @client.on(JoinEvent)
        async def on_join(event: JoinEvent):
            global displayed_viewers
            if event.user is None or narrator is None:
                return
            displayed_viewers = max(MIN_VIEWERS_DISPLAY, displayed_viewers + 1)
            now = time.time()
            if now - narrator.last_join_tts > 8.5:
                narrator.last_join_tts = now
                clean_nick = (event.user.nickname or event.user.unique_id)[:14].replace("_", " ")
                narrator.say(
                    f"¡Bienvenido {clean_nick} al live de batería! Comenta A o B para votar por la siguiente canción."
                )

        @client.on(CommentEvent)
        async def on_comment(event: CommentEvent):
            if event.user is None:
                return
            register_real_interaction()
            raw_comment = event.comment.strip()
            uid = f"tt_{event.user.unique_id}"
            nick = event.user.nickname or event.user.unique_id
            avatar = extract_avatar_url(event.user)

            print(f"[TikTok Chat] 🔴 @{nick}: {raw_comment}")

            if es_alerta_copyright_chat(raw_comment):
                trigger_copyright_protection(f"Alerta en TikTok por @{nick[:10]}")
                return

            voto = detectar_voto(raw_comment)

            if voto == "A":
                join_team(uid, nick, "A", avatar, announce_tts=True, is_bot=False, platform="TT")
            elif voto == "B":
                join_team(uid, nick, "B", avatar, announce_tts=True, is_bot=False, platform="TT")
            else:
                with state_lock:
                    if uid in players:
                        players[uid]["last_active"] = time.time()
                        players[uid]["participated_this_song"] = True
                    floating_texts.append({
                        "text": f"💬 @{nick[:10]}: {raw_comment[:26]}",
                        "x": WIDTH // 2,
                        "y": HEIGHT * 0.52,
                        "vy": -0.9,
                        "life": 85,
                        "color": (255, 240, 180)
                    })
                if narrator and len(raw_comment) >= 2:
                    cur_t = current_song["title"] if current_song else "Cover de Batería"
                    ta = option_a_song["title"] if option_a_song else "Opción A"
                    tb = option_b_song["title"] if option_b_song else "Opción B"
                    narrator.ask_ollama_and_say(nick, raw_comment, cur_t, ta, tb)

        @client.on(LikeEvent)
        async def on_like(event: LikeEvent):
            if event.user is None:
                return
            register_real_interaction()
            uid = f"tt_{event.user.unique_id}"
            likes = getattr(event, "count", 1) or 1
            trigger_attack(uid, multiplier=min(likes, 12), is_flower=False)

        @client.on(GiftEvent)
        async def on_gift(event: GiftEvent):
            if event.user is None or event.gift is None:
                return
            if getattr(event, "streaking", False):
                return
            register_real_interaction()
            uid = f"tt_{event.user.unique_id}"
            nick = event.user.nickname or event.user.unique_id
            count = getattr(event, "repeat_count", 1) or 1

            if uid not in players:
                team = "A" if score_a <= score_b else "B"
                join_team(uid, nick, team, extract_avatar_url(event.user), announce_tts=False, is_bot=False, platform="TT")

            trigger_attack(uid, multiplier=count, is_flower=True)

        try:
            client.run()
        except Exception:
            tiktok_connected = False
            time.sleep(8)


# ================= FUNCIONES VISUALES Y HUD DE VOTACIÓN =================
def draw_star(surface, center, radius, color):
    pts = []
    for i in range(10):
        angle = i * math.pi / 5 - math.pi / 2
        r = radius if i % 2 == 0 else radius * 0.45
        pts.append((center[0] + math.cos(angle) * r, center[1] + math.sin(angle) * r))
    pygame.draw.polygon(surface, color, pts)


def draw_voting_power_bar(surface, ratio_a, font_score, t_sec):
    cx, cy = WIDTH // 2, 238
    length = 420
    x1, x2 = cx - length // 2, cx + length // 2
    split_x = int(x1 + length * ratio_a)

    pygame.draw.rect(surface, (12, 10, 20), (x1 - 3, cy - 11, length + 6, 22), border_radius=10)
    if split_x > x1:
        pygame.draw.rect(surface, COLOR_DEMON, (x1, cy - 8, split_x - x1, 16), border_radius=8)
    if x2 > split_x:
        pygame.draw.rect(surface, COLOR_ANGEL, (split_x, cy - 8, x2 - split_x, 16), border_radius=8)

    flicker = int(math.sin(t_sec * 14) * 3)
    pygame.draw.circle(surface, (255, 140, 40), (split_x, cy), 13 + flicker)
    pygame.draw.circle(surface, (255, 240, 180), (split_x, cy), 7)

    sa_surf = font_score.render(f"{score_a:,} pts", (255, 220, 150))
    sb_surf = font_score.render(f"{score_b:,} pts", (185, 240, 255))
    surface.blit(sa_surf, (x1, cy + 12))
    surface.blit(sb_surf, (x2 - sb_surf.get_width(), cy + 12))


# ================= BUCLE PRINCIPAL =================
def main():
    global score_a, score_b, use_chroma, round_banner_timer, round_winner_text, ENABLE_BOTS
    global video_library, current_song, option_a_song, option_b_song, narrator
    global copyright_skip_triggered, copyright_skip_reason

    setup_assets()
    pygame.display.init()
    try:
        pygame.font.init()
    except Exception:
        pass

    audio = AudioManager()
    narrator = NarratorTTS()
    video_player = DrumVideoPlayer(WIDTH, HEIGHT, target_fps=30)
    bot_manager = BotActivityManager()

    screen = pygame.display.set_mode((WIDTH, HEIGHT))
    pygame.display.set_caption("🥁 Multi-Stream Live (Anti-Copyright Activo) - Vota por el Siguiente Cover")
    clock = pygame.time.Clock()

    sounds["vote_a"] = audio.load_sound(os.path.join(ASSETS_DIR, "arcade_vote_a.wav"), 0.65)
    sounds["vote_b"] = audio.load_sound(os.path.join(ASSETS_DIR, "arcade_vote_b.wav"), 0.65)
    sounds["combo"] = audio.load_sound(os.path.join(ASSETS_DIR, "arcade_combo.wav"), 0.75)
    sounds["laser"] = audio.load_sound(os.path.join(ASSETS_DIR, "arcade_laser.wav"), 0.35)
    sounds["powerup"] = audio.load_sound(os.path.join(ASSETS_DIR, "arcade_powerup.wav"), 0.80)
    sounds["victory"] = audio.load_sound(os.path.join(ASSETS_DIR, "arcade_victory.wav"), 0.80)

    init_high_fire(count=65)

    video_library = load_video_library(VIDEOS_DIR)
    if video_library:
        current_song = random.choice(video_library)
        option_a_song, option_b_song = pick_two_candidates({current_song["path"]})
        video_player.play(current_song)
    else:
        current_song = {"title": "Sin videos en carpeta", "path": "", "filename": ""}
        option_a_song = {"title": "Canción A", "path": "", "filename": ""}
        option_b_song = {"title": "Canción B", "path": "", "filename": ""}

    font_title = HybridFont("Impact", 24, bold=True)
    font_sub = HybridFont("Arial", 15, bold=True)
    font_small = HybridFont("Arial", 12, bold=True)
    font_tiny = HybridFont("Arial", 10, bold=True)

    # Iniciar los 4 hilos: TikTok + Twitch + YouTube (@rasec555) + Facebook (theJulius555)
    threading.Thread(target=start_tiktok_thread, daemon=True).start()
    threading.Thread(target=start_twitch_thread, daemon=True).start()
    threading.Thread(target=start_youtube_thread, daemon=True).start()
    threading.Thread(target=start_facebook_thread, daemon=True).start()

    announce_current_vote(priority=True)
    last_promo_tts = time.time()

    running = True

    def clean_inactive_bubbles():
        """Elimina las burbujas de usuarios que ya se salieron para no saturar la pantalla."""
        now = time.time()
        with state_lock:
            to_remove = [
                uid for uid, p in players.items()
                if not p.get("participated_this_song", False)
                or p.get("is_bot", False)
                or (now - p.get("last_active", 0) > 120.0)
            ]
            for uid in to_remove:
                players.pop(uid, None)

            for p in players.values():
                p["participated_this_song"] = False
                p["target_radius"] = 20.0
                p["power"] = 25
                p["flowers"] = 0

    def advance_to_winning_song():
        global score_a, score_b, current_song, option_a_song, option_b_song, round_banner_timer, round_winner_text
        if not video_library:
            return

        if score_a >= score_b:
            winner = option_a_song
            round_winner_text = f"🏆 ¡GANÓ A: {winner['title'][:22]}!"
        else:
            winner = option_b_song
            round_winner_text = f"🏆 ¡GANÓ B: {winner['title'][:22]}!"

        sounds["victory"].play()
        round_banner_timer = 210

        current_song = winner
        video_player.play(current_song)

        option_a_song, option_b_song = pick_two_candidates({current_song["path"]})
        score_a, score_b = 1000, 1000

        clean_inactive_bubbles()

        narrator.say(
            f"¡Terminó el cover! Con sus votos ganó {current_song['title']}. "
            f"¡Ahora voten con A por {option_a_song['title']}, o con B por {option_b_song['title']}!",
            priority=True,
        )

    def ban_current_song_and_skip(reason="Copyright detectado"):
        """
        Bloquea la canción actual en copyright_blacklist.json, la saca de memoria
        y salta inmediatamente a la siguiente canción sin interrumpir el stream.
        """
        global current_song, option_a_song, option_b_song, score_a, score_b, round_banner_timer, round_winner_text
        if not current_song:
            return

        banned_title = current_song["title"]
        save_to_copyright_blacklist(current_song, reason=reason)

        video_library[:] = [
            v for v in video_library
            if v["path"] != current_song["path"] and v["title"].lower() != banned_title.lower()
        ]

        round_winner_text = f"🚫 EXCLUIDA POR COPYRIGHT: {banned_title[:18]}"
        round_banner_timer = 220

        if not video_library:
            video_player.stop()
            return

        next_song = option_a_song if score_a >= score_b else option_b_song
        if not next_song or next_song["path"] == current_song["path"]:
            next_song = random.choice(video_library)

        current_song = next_song
        video_player.play(current_song)

        option_a_song, option_b_song = pick_two_candidates({current_song["path"]})
        score_a, score_b = 1000, 1000
        clean_inactive_bubbles()

        narrator.say(
            f"¡Saltamos la canción anterior por derechos de autor! "
            f"Ahora suena {current_song['title']}. ¡Sigan votando con A o B!",
            priority=True,
        )

    while running:
        t_sec = pygame.time.get_ticks() / 1000.0

        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                running = False
            elif ev.type == pygame.KEYDOWN:
                if ev.key in (pygame.K_a, pygame.K_1):
                    uid = random.choice(FAKE_USERS_POOL)
                    join_team(uid, uid, "A", is_bot=True, platform=random.choice(["TT", "TW", "YT", "FB"]))
                elif ev.key in (pygame.K_b, pygame.K_2):
                    uid = random.choice(FAKE_USERS_POOL)
                    join_team(uid, uid, "B", is_bot=True, platform=random.choice(["TT", "TW", "YT", "FB"]))
                elif ev.key in (pygame.K_t, pygame.K_SPACE) and players:
                    trigger_attack(random.choice(list(players.keys())), multiplier=3, is_flower=False)
                elif ev.key in (pygame.K_f, pygame.K_r) and players:
                    trigger_attack(random.choice(list(players.keys())), multiplier=1, is_flower=True)
                elif ev.key == pygame.K_n:
                    advance_to_winning_song()
                # X -> Botón de pánico Anti-Copyright: Banea la canción actual para siempre y la salta
                elif ev.key == pygame.K_x:
                    trigger_copyright_protection("Marcada manualmente con tecla [X]")
                elif ev.key == pygame.K_i:
                    ENABLE_BOTS = not ENABLE_BOTS
                    print(f"[Control Interno] Actividad simulada: {'ACTIVA' if ENABLE_BOTS else 'PAUSADA'}")
                elif ev.key == pygame.K_m:
                    bot_nick = random.choice(FAKE_USERS_POOL)
                    narrator.generate_ai_bot_comment(
                        bot_nick,
                        current_song["title"],
                        option_a_song["title"],
                        option_b_song["title"],
                    )
                elif ev.key == pygame.K_v:
                    announce_current_vote(priority=True)
                elif ev.key == pygame.K_c:
                    use_chroma = not use_chroma

        if copyright_skip_triggered:
            copyright_skip_triggered = False
            ban_current_song_and_skip(reason=copyright_skip_reason)

        bot_manager.update()

        if video_player.finished:
            advance_to_winning_song()

        if time.time() - last_promo_tts > 60.0:
            last_promo_tts = time.time()
            announce_current_vote(priority=False)

        # 1. Dibujar el Video de Batería Actual de Fondo con Zoom Lento y Color Sutil al Ritmo
        if use_chroma:
            screen.fill(CHROMA_GREEN)
        else:
            v_frame = video_player.get_frame()
            if v_frame:
                # EFECTO 1: Zoom lento (Ken Burns)
                zoom = 1.0 + 0.20 * (0.5 + 0.5 * math.sin(t_sec * 0.6))
                zw = int(WIDTH * zoom)
                zh = int(HEIGHT * zoom)
                scaled_frame = pygame.transform.smoothscale(v_frame, (zw, zh))
                zx = (WIDTH - zw) // 2
                zy = (HEIGHT - zh) // 2

                # EFECTO 2: Tinte sutil con alfa (sin quemar los blancos)
                beat_pulse = abs(math.sin(t_sec * math.pi * 2 * (125 / 60)))
                tint_alpha = int(4 + 8 * beat_pulse)  # Muy suave y elegante
                tint_color = (255, 100, 30) if score_a >= score_b else (30, 140, 255)

                tint_surface = pygame.Surface((WIDTH, HEIGHT), pygame.SRCALPHA)
                tint_surface.fill((*tint_color, tint_alpha))

                screen.blit(scaled_frame, (zx, zy))
                screen.blit(tint_surface, (0, 0))  # Blit normal con alfa para no saturar
            else:
                screen.fill((16, 14, 24))

            hud_overlay = pygame.Surface((WIDTH, HEIGHT), pygame.SRCALPHA)
            pygame.draw.rect(hud_overlay, (10, 8, 18, 185), (0, 0, WIDTH, 272))
            pygame.draw.rect(hud_overlay, (10, 8, 18, 130), (0, HEIGHT - 125, WIDTH, 125))
            screen.blit(hud_overlay, (0, 0))

            update_and_draw_high_fire(screen, t_sec)

        # 2. Físicas de Flotación y Avatares Votantes
        with state_lock:
            p_list = list(players.values())
            boss_a = max((p for p in p_list if p["team"] == "A"), key=lambda x: x["power"], default=None)
            boss_b = max((p for p in p_list if p["team"] == "B"), key=lambda x: x["power"], default=None)

            for i, p in enumerate(p_list):
                anchor = ANCHOR_A if p["team"] == "A" else ANCHOR_B
                is_boss = (p is boss_a) or (p is boss_b)

                spring_force = (p["target_radius"] - p["radius"]) * 0.18
                p["radius_vel"] = (p["radius_vel"] + spring_force) * 0.76
                p["radius"] = max(8.0, p["radius"] + p["radius_vel"])

                float_ox = math.cos(t_sec * p["float_speed"] + p["float_phase"]) * p["float_amp"]
                float_oy = math.sin(t_sec * (p["float_speed"] * 1.25) + p["float_phase"]) * p["float_amp"]

                target_x = anchor[0] + float_ox
                target_y = anchor[1] + float_oy

                pull = 0.032 if is_boss else 0.016
                dx = target_x - p["x"]
                dy = target_y - p["y"]

                p["vx"] = (p["vx"] + dx * pull - dy * 0.002 * p["orbit_dir"]) * 0.86
                p["vy"] = (p["vy"] + dy * pull + dx * 0.002 * p["orbit_dir"]) * 0.86

                for j in range(i + 1, len(p_list)):
                    other = p_list[j]
                    ox, oy = other["x"] - p["x"], other["y"] - p["y"]
                    dist = math.hypot(ox, oy) or 0.1
                    min_d = p["radius"] + other["radius"] + 4
                    if dist < min_d:
                        overlap = (min_d - dist) * 0.45
                        nx, ny = ox / dist, oy / dist
                        p["x"] -= nx * overlap
                        p["y"] -= ny * overlap
                        other["x"] += nx * overlap
                        other["y"] += ny * overlap

                p["x"] += p["vx"]
                p["y"] += p["vy"]

            for p in sorted(p_list, key=lambda x: x["radius"]):
                is_boss = (p is boss_a) or (p is boss_b)
                bob_y = math.sin(t_sec * p["float_speed"] * 1.6 + p["float_phase"]) * 4.0
                pos = (int(p["x"]), int(p["y"] + bob_y))
                r = int(p["radius"] + (4 if is_boss else 0))

                border_col = COLOR_DEMON if p["team"] == "A" else COLOR_ANGEL
                glow_col = COLOR_DEMON_GLOW if p["team"] == "A" else COLOR_ANGEL_GLOW

                if p["flowers"] > 0 or is_boss:
                    aura_r = r + 4 + int(math.sin(t_sec * 6 + p["float_phase"]) * 2.5)
                    pygame.draw.circle(screen, COLOR_GOLD if p["flowers"] > 0 else glow_col, pos, aura_r, 2)

                if p["base_avatar"]:
                    scaled = pygame.transform.smoothscale(p["base_avatar"], (r * 2, r * 2))
                    screen.blit(scaled, (pos[0] - r, pos[1] - r))
                else:
                    pygame.draw.circle(screen, p["seed_color"], pos, r)

                ini = font_small.render(p["nickname"][:2].upper(), (255, 255, 255), shadow_color=(0, 0, 0))
                screen.blit(ini, ini.get_rect(center=pos))

                pygame.draw.circle(screen, border_col, pos, r, 3)

                plat = p.get("platform", "TT")
                if plat == "TW":
                    pygame.draw.circle(screen, COLOR_TWITCH, pos, r + 2, 2)
                elif plat == "YT":
                    pygame.draw.circle(screen, COLOR_YOUTUBE, pos, r + 2, 2)
                elif plat == "FB":
                    pygame.draw.circle(screen, COLOR_FACEBOOK, pos, r + 2, 2)

                if is_boss:
                    draw_star(screen, (pos[0], pos[1] - r - 8), 7, COLOR_GOLD)

                if is_boss or p["flowers"] > 0 or r >= 20:
                    if plat == "TW":
                        name_col = (215, 180, 255)
                    elif plat == "YT":
                        name_col = (255, 175, 175)
                    elif plat == "FB":
                        name_col = (165, 210, 255)
                    else:
                        name_col = (255, 240, 165)
                    ntxt = font_tiny.render(f"@{p['nickname'][:11]}", name_col)
                    screen.blit(ntxt, ntxt.get_rect(center=(pos[0], pos[1] - r - 15)))

            for rb in rose_bursts[:]:
                rb["x"] += rb["vx"]
                rb["y"] += rb["vy"]
                rb["life"] -= 1
                pygame.draw.circle(screen, rb["color"], (int(rb["x"]), int(rb["y"])), rb["size"] // 2)
                if rb["life"] <= 0:
                    rose_bursts.remove(rb)

            for proj in projectiles[:]:
                dx, dy = proj["tx"] - proj["x"], proj["ty"] - proj["y"]
                dist = math.hypot(dx, dy)
                if dist < 18:
                    projectiles.remove(proj)
                else:
                    vx, vy = (dx / dist) * 17, (dy / dist) * 17
                    pygame.draw.line(
                        screen, proj["color"],
                        (int(proj["x"]), int(proj["y"])),
                        (int(proj["x"] - vx * 1.3), int(proj["y"] - vy * 1.3)),
                        max(2, proj["size"] - 1)
                    )
                    proj["x"] += vx
                    proj["y"] += vy
                    pygame.draw.circle(screen, (255, 255, 255), (int(proj["x"]), int(proj["y"])), proj["size"])

            for sw in shockwaves[:]:
                sw["r"] += 5.5
                pygame.draw.circle(screen, sw["color"], (int(sw["x"]), int(sw["y"])), int(sw["r"]), 3)
                stxt = font_small.render(sw["text"], COLOR_GOLD)
                screen.blit(stxt, stxt.get_rect(center=(int(sw["x"]), int(sw["y"]) - int(sw["r"]) - 10)))
                if sw["r"] >= sw["max_r"]:
                    shockwaves.remove(sw)

            for ft in floating_texts[:]:
                ft["y"] += ft["vy"]
                ft["life"] -= 1
                tsurf = font_small.render(ft["text"], ft["color"])
                screen.blit(tsurf, tsurf.get_rect(center=(int(ft["x"]), int(ft["y"]))))
                if ft["life"] <= 0:
                    floating_texts.remove(ft)

        # ================= 3. HUD SUPERIOR Y CONTADOR DE CONECTADOS =================
        now_playing_str = f"🥁 SONANDO: {current_song['title'][:24]}" if current_song else "🥁 CARGANDO..."
        np_surf = font_small.render(now_playing_str, COLOR_GOLD)
        screen.blit(np_surf, (18, 14))

        pygame.draw.rect(screen, (28, 16, 36), (WIDTH - 172, 10, 154, 26), border_radius=12)
        pygame.draw.rect(screen, (255, 65, 95), (WIDTH - 172, 10, 154, 26), 2, border_radius=12)
        if int(t_sec * 2) % 2 == 0:
            pygame.draw.circle(screen, (255, 45, 70), (WIDTH - 158, 23), 5)
        viewers_surf = font_tiny.render(f"👁 {displayed_viewers} conectados", (255, 240, 245))
        screen.blit(viewers_surf, viewers_surf.get_rect(center=(WIDTH - 88, 23)))

        title_surf = font_title.render("🔥 VOTA POR EL SIGUIENTE COVER 🔥", (255, 245, 220))
        screen.blit(title_surf, title_surf.get_rect(center=(WIDTH // 2, 58)))

        # Cajas de Votación A y B (más cómodas para que los textos entren perfecto)
        pygame.draw.rect(screen, (38, 16, 16), (18, 84, 242, 98), border_radius=10)
        pygame.draw.rect(screen, COLOR_DEMON, (18, 84, 242, 98), 2, border_radius=10)

        pygame.draw.rect(screen, (14, 26, 42), (WIDTH - 260, 84, 242, 98), border_radius=10)
        pygame.draw.rect(screen, COLOR_ANGEL, (WIDTH - 260, 84, 242, 98), 2, border_radius=10)

        ha_surf = font_sub.render("COMENTA: A / a", COLOR_DEMON_GLOW)
        hb_surf = font_sub.render("COMENTA: B / b", COLOR_ANGEL_GLOW)
        screen.blit(ha_surf, ha_surf.get_rect(center=(139, 101)))
        screen.blit(hb_surf, hb_surf.get_rect(center=(WIDTH - 139, 101)))

        title_a = option_a_song["title"] if option_a_song else "Canción A"
        title_b = option_b_song["title"] if option_b_song else "Canción B"

        a_line1, a_line2 = title_a[:22], title_a[22:44]
        b_line1, b_line2 = title_b[:22], title_b[22:44]

        screen.blit(font_small.render(a_line1, (255, 255, 255)), font_small.render(a_line1, (255, 255, 255)).get_rect(center=(139, 128)))
        if a_line2:
            screen.blit(font_tiny.render(a_line2, (235, 210, 200)), font_tiny.render(a_line2, (235, 210, 200)).get_rect(center=(139, 150)))

        screen.blit(font_small.render(b_line1, (255, 255, 255)), font_small.render(b_line1, (255, 255, 255)).get_rect(center=(WIDTH - 139, 128)))
        if b_line2:
            screen.blit(font_tiny.render(b_line2, (200, 225, 245)), font_tiny.render(b_line2, (200, 225, 245)).get_rect(center=(WIDTH - 139, 150)))

        inst_surf = font_small.render("¡Tap Tap / !tap para atacar  •  🌹, Bits o Estrellas = Super Voto!", (255, 230, 140))
        screen.blit(inst_surf, inst_surf.get_rect(center=(WIDTH // 2, 204)))

        ratio_a = score_a / max(1, score_a + score_b)
        draw_voting_power_bar(screen, ratio_a, font_small, t_sec)

        if narrator and narrator.speaking:
            pygame.draw.rect(screen, (20, 14, 34), (16, 875, WIDTH - 32, 46), border_radius=10)
            pygame.draw.rect(screen, COLOR_GOLD, (16, 875, WIDTH - 32, 46), 2, border_radius=10)
            sub_short = narrator.current_subtitle[:58] + ("..." if len(narrator.current_subtitle) > 58 else "")
            tts_surf = font_tiny.render(f"🔊 {sub_short}", (255, 240, 185))
            screen.blit(tts_surf, tts_surf.get_rect(center=(WIDTH // 2, 898)))

        if round_banner_timer > 0:
            round_banner_timer -= 1
            pygame.draw.rect(screen, (22, 14, 32), (24, HEIGHT // 2 - 42, WIDTH - 48, 84), border_radius=14)
            pygame.draw.rect(screen, COLOR_GOLD, (24, HEIGHT // 2 - 42, WIDTH - 48, 84), 3, border_radius=14)
            b_surf = font_sub.render(round_winner_text, COLOR_GOLD)
            screen.blit(b_surf, b_surf.get_rect(center=(WIDTH // 2, HEIGHT // 2)))

        # Cintillo inferior limpio mostrando las 4 plataformas
        any_live = tiktok_connected or twitch_connected or youtube_connected or facebook_connected
        status_col = COLOR_NEON_GREEN if any_live else (255, 215, 110)
        status_str = "🔴 TikTok  |  🟣 Twitch: bardack21  |  ▶️ YT: @rasec555  |  🔵 FB: theJulius555"
        st_surf = font_tiny.render(status_str, status_col)
        screen.blit(st_surf, st_surf.get_rect(center=(WIDTH // 2, HEIGHT - 18)))

        pygame.display.flip()
        clock.tick(FPS)

    video_player.stop()
    pygame.quit()


if __name__ == "__main__":
    main()
