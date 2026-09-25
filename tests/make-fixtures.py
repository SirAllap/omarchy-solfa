#!/usr/bin/env python3
"""Turn raw InnerTube captures into invented test fixtures.

    tests/make-fixtures.py RAW_DIR OUT_DIR

The structure of every reply is kept, so the parsers meet the real shapes.
Everything that names something (titles, artists, ids, image URLs) is
replaced by an invented value derived from a hash, the same input always
giving the same output, so links between items stay consistent. Tracking
blobs are dropped. UI words (type labels, separators), durations and years
are kept, because the parsers must cope with them.

The raw captures never go into the repository.
"""
import hashlib
import json
import pathlib
import re
import sys

DROP_KEYS = {
    "trackingParams", "clickTrackingParams", "serviceTrackingParams",
    "responseContext", "loggingContext", "frameworkUpdates", "adSignalsInfo",
    "loggingDirectives", "impressionEndpoints", "feedbackEndpoint",
}

# UI words the page uses as labels; they are not names, keep them.
KEEP_TEXT = {
    "Song", "Songs", "Video", "Videos", "Album", "Albums", "Single", "Singles",
    "EP", "Artist", "Artists", "Playlist", "Playlists", "Episode", "Podcast",
    "Profile", "Top songs", "Top result", "Fans might also like", "Featured on",
    "Show all", "More", "Shuffle", "Radio", "Mix", "Lyrics not available",
    "Community playlists", "Featured playlists", "Up next", "Lyrics", "Related",
}
SEPARATORS = {" • ", " & ", ", ", " · ", "•", " "}

SYL = ["la", "mo", "ri", "ven", "sol", "ka", "de", "lu", "na", "tor", "mi",
       "sa", "vel", "ro", "fen", "da", "li", "quo", "zen", "ta", "bri", "el"]


def h(s, n=8):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()[:n]


def fake_words(s):
    """Two or three invented words, stable for the same input."""
    d = hashlib.sha256(s.encode("utf-8")).digest()
    words = []
    for w in range(2 + d[0] % 2):
        word = "".join(SYL[d[1 + w * 3 + k] % len(SYL)] for k in range(2))
        words.append(word.capitalize())
    return " ".join(words)


ID_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"


def fake_id(value):
    """Same length, same known prefix, invented tail."""
    for prefix in ("MPREb_", "MPLYt_", "MPTRt_", "OLAK5uy_", "RDAMVM", "RDAMPL",
                   "RDCLAK5uy_", "VLOLAK5uy_", "VLRDCLAK5uy_", "VL", "UC", "PL",
                   "RD", "MPSP", "FEmusic_", "LM"):
        if value.startswith(prefix):
            break
    else:
        prefix = ""
    if value in ("LM", "VLLM") or value.startswith("FEmusic_"):
        return value
    tail = value[len(prefix):]
    d = hashlib.sha256(value.encode("utf-8")).digest()
    out = "".join(ID_ALPHABET[d[i % len(d)] % 64] for i in range(len(tail)))
    return prefix + out


TIME_RE = re.compile(r"^\d{1,2}:\d{2}(:\d{2})?$")
YEAR_RE = re.compile(r"^(19|20)\d{2}$")
NUM_RE = re.compile(r"^[\d.,]+\s*[KMB]?\s")


def fake_text(s):
    if s in KEEP_TEXT or s in SEPARATORS or s.strip() == "":
        return s
    if TIME_RE.match(s) or YEAR_RE.match(s):
        return s
    if NUM_RE.match(s):
        # "1.2M views" / "12 songs": keep the shape, change the number
        return re.sub(r"[\d.,]+", str(int(h(s, 3), 16) % 900 + 10), s, count=1)
    return fake_words(s)


ID_KEYS = {"videoId", "playlistId", "browseId", "playlistSetVideoId", "channelId",
           "externalChannelId", "setVideoId", "videoIds"}
ENUM_RE = re.compile(r"^[A-Z0-9_]+$")
DIGITS_RE = re.compile(r"^-?\d+$")
IMAGE_HOSTS = ("googleusercontent", "ytimg", "ggpht")


def is_protocol_key(k):
    kl = k.lower()
    return kl.endswith("params") or kl in ("continuation", "token", "nextcontinuationdata", "signal")


def scrub_string(k, v):
    if k in ID_KEYS:
        return fake_id(v)
    if is_protocol_key(k) or ENUM_RE.match(v) or DIGITS_RE.match(v):
        return v
    if v.startswith("http") or v.startswith("vnd.") or v.startswith("//"):
        if any(host in v for host in IMAGE_HOSTS):
            size = re.search(r"=(w\d+-h\d+[^/]*)$", v)
            return "https://lh3.googleusercontent.com/fixture-" + h(v, 12) + ("=" + size.group(1) if size else "")
        return "https://example.invalid/fixture-" + h(v, 12)
    if v.startswith("/"):
        return "/fixture-" + h(v, 12)
    return fake_text(v)


def scrub(o, key=""):
    if isinstance(o, dict):
        return {k: scrub(v, k) for k, v in o.items() if k not in DROP_KEYS}
    if isinstance(o, list):
        # Long lists only repeat the same shape; eight items are enough.
        return [scrub(x, key) for x in o[:8]]
    if isinstance(o, str):
        return scrub_string(key, o)
    return o


def main():
    raw, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for f in sorted(raw.glob("*.json")):
        data = scrub(json.loads(f.read_text()))
        (out / f.name).write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n")
        print(f.name, (out / f.name).stat().st_size)


if __name__ == "__main__":
    main()
