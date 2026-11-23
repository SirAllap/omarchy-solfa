#!/bin/bash
# live-lab.sh — a private, invisible Hyprland (headless backend) running the real
# Omarchy shell with a COPY of this plugin and the fake engine, so the bar/panel
# join can be tuned against the real compositor. Nothing appears on any screen.
#
#   tests/live-lab.sh start [WORKTREE]   # WORKTREE defaults to this repo
#   tests/live-lab.sh shot  LABEL        # grim -> ~/Documents/.../app/lab-LABEL*.png
#   tests/live-lab.sh stop
#
# SCALE=1.25 (default) | 1 | 1.5 | 2     OPEN=0 skips opening the panel
# LAB_STATE=playing (default) | idle | off   what the pill shows: the fake engine's song / no song / the
#                                            engine stopped through the bridge socket (engine.stop), as the panel's off switch does
#                                            (a fresh lab is off until the first start: after `start`, run `engine-start` for idle/playing,
#                                            `engine-stop` for off)
# LAB_THEME=owner (default) | light | dark | grey | purple   the Omarchy theme colours (bar + popup), copied nowhere
# LAB_BAR=owner (default) | opaque | glassy  the bar look (glassy = translucent, alpha <= 0.35)
# Everything lives under ~/.cache/agx-vt/live-lab. Only PIDs this script started
# (recorded in $LAB/pids) are ever signalled; never a pkill by name.
set -u
LAB="$HOME/.cache/agx-vt/live-lab"
RUN_REAL="$LAB/run"       # where the private runtime dir really lives
# Unix socket paths top out near 108 bytes and Hyprland's own is ~100 long, so the
# private XDG_RUNTIME_DIR is this short alias to $RUN_REAL (made at start, removed at stop).
RUN="/run/user/$(id -u)/ll"
PHOME="$LAB/home"         # private HOME
PIDS="$LAB/pids"
LIVEF="$LAB/live.txt"     # the live session's values, read once at start
OUTDIR="${LAB_OUT:-$HOME/Documents/projects/agentglass/solfa-redesign/app}"
SCALE="${SCALE:-1.25}"
PID_ID="io.github.sirallap.solfa"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
OMARCHY="/usr/share/omarchy"
BASE_PATH="/usr/local/bin:/usr/bin:/bin"

die() { echo "live-lab: $*" >&2; exit 1; }

load_private() {  # PSIG / PWDISP of the private instance (written by start)
  [ -f "$LAB/private.txt" ] || die "not started (no $LAB/private.txt)"
  . "$LAB/private.txt"
  [ -f "$LIVEF" ] && . "$LIVEF"
}

# Every call into a compositor/shell goes through priv(). It refuses to run unless
# the private values are set and differ from the live ones read at start, and it
# hands the command an env that names ONLY the private instance (XDG_RUNTIME_DIR
# is the private dir, so hyprctl/grim/quickshell cannot even find the live sockets).
assert_private() {
  [ -n "${PSIG:-}" ] && [ -n "${PWDISP:-}" ] || die "private instance values missing"
  [ "$PSIG" != "${LIVE_SIG:-}" ] || die "ABORT: private signature equals the live one"
  [ "$RUN" != "${LIVE_RT:-}" ] || die "ABORT: private runtime dir equals the live one"
  [ -S "$PWDISP" ] || die "private display socket $PWDISP is gone"
  [ "$PWDISP" != "${LIVE_WD:-}" ] || die "ABORT: private display equals the live one"
  # Belt and braces: refuse to call anything unless the private instance's own socket
  # exists, so a half-started lab can never fall through to a default socket.
  [ -S "$RUN/hypr/$PSIG/.socket.sock" ] || die "ABORT: private hyprland socket missing; not calling anything"
}
priv() {  # priv cmd args... — run with a clean, private-only environment
  assert_private
  env -i PATH="$BASE_PATH" LANG="${LANG:-C.UTF-8}" HOME="$PHOME" \
    XDG_CONFIG_HOME="$PHOME/.config" XDG_STATE_HOME="$PHOME/.local/state" \
    XDG_CACHE_HOME="$PHOME/.cache" XDG_DATA_HOME="$PHOME/.local/share" \
    XDG_RUNTIME_DIR="$RUN" WAYLAND_DISPLAY="$PWDISP" HYPRLAND_INSTANCE_SIGNATURE="$PSIG" \
    XDG_CURRENT_DESKTOP=Hyprland XDG_SESSION_TYPE=wayland QT_QPA_PLATFORM=wayland \
    OMARCHY_PATH="$OMARCHY" "$@"
}
bg() {  # bg NAME cmd... — a priv() command in the background, PID recorded
  local name="$1"; shift
  priv "$@" >"$LAB/$name.log" 2>&1 &
  echo "$name $!" >> "$PIDS"
}

cmd_start() {
  local wt="${1:-$(cd "$SELF_DIR/.." && pwd)}"
  [ -f "$wt/manifest.json" ] || die "$wt is not a Solfa tree (no manifest.json)"
  if [ -s "$PIDS" ]; then
    while read -r _ p; do kill -0 "$p" 2>/dev/null && die "a lab is already running; run stop first"; done < "$PIDS"
  fi
  rm -rf "$LAB"; mkdir -p "$RUN_REAL" "$PHOME"; chmod 700 "$RUN_REAL"; : > "$PIDS"
  [ ! -e "$RUN" ] || [ -L "$RUN" ] || die "$RUN exists and is not our link"
  ln -sfn "$RUN_REAL" "$RUN"

  # The live session's values, by name, once. Never the whole environment.
  { echo "LIVE_SIG='${HYPRLAND_INSTANCE_SIGNATURE-}'"
    echo "LIVE_WD='${WAYLAND_DISPLAY-}'"
    echo "LIVE_RT='${XDG_RUNTIME_DIR-}'"; } > "$LIVEF"
  . "$LIVEF"
  [ "$RUN" != "$LIVE_RT" ] || die "private runtime dir equals the live one"
  echo "live   : sig=${LIVE_SIG:-<unset>} display=${LIVE_WD:-<unset>} runtime=${LIVE_RT:-<unset>}"

  # -- isolated HOME: only what the shell needs --------------------------------
  local pc="$PHOME/.config/omarchy" ps="$PHOME/.local/state/omarchy"
  mkdir -p "$pc/plugins" "$ps/current/theme" "$PHOME/.cache" "$PHOME/.local/share"
  rsync -a --exclude=.git --exclude=mockups --exclude=preview.png "$wt/" "$pc/plugins/$PID_ID/"
  local fake="$pc/plugins/$PID_ID/tests/fake_engine.py"
  chmod +x "$fake"
  # light theme + the owner's shell.toml, copied (never linked, never written back)
  local th="$HOME/.local/state/omarchy/current/theme"
  for f in colors.toml shell.toml light.mode icons.theme; do [ -f "$th/$f" ] && cp "$th/$f" "$ps/current/theme/$f"; done
  [ -f "$ps/current/theme/light.mode" ] || touch "$ps/current/theme/light.mode"
  case "${LAB_THEME:-owner}" in   # Omarchy's own white (light) / tokyo-night (dark) values, as tests/test_bar_states.py
    light) printf 'foreground = "#000000"\nbackground = "#ffffff"\naccent = "#6e6e6e"\n' > "$ps/current/theme/colors.toml"
           printf '[bar]\nbackground = "#f5f5f5"\ntext = "#000000"\n[popups]\nbackground = "#ffffff"\ntext = "#000000"\n' > "$ps/current/theme/shell.toml"
           touch "$ps/current/theme/light.mode" ;;
    dark)  printf 'foreground = "#a9b1d6"\nbackground = "#1a1b26"\naccent = "#7aa2f7"\n' > "$ps/current/theme/colors.toml"
           printf '[bar]\nbackground = "#13141c"\ntext = "#a9b1d6"\n[popups]\nbackground = "#1a1b26"\ntext = "#a9b1d6"\n' > "$ps/current/theme/shell.toml"
           rm -f "$ps/current/theme/light.mode" ;;
    # the owner's grey translucent bar (live-off-rest-2): a mid-grey bar, faint grey ink
    grey)  printf 'foreground = "#9a9aa8"\nbackground = "#7f7f8c"\naccent = "#6e6e80"\n' > "$ps/current/theme/colors.toml"
           printf '[bar]\nbackground = "#7f7f8c"\ntext = "#9a9aa8"\n[popups]\nbackground = "#7f7f8c"\ntext = "#9a9aa8"\n' > "$ps/current/theme/shell.toml"
           rm -f "$ps/current/theme/light.mode" ;;
    # the worst case (live-off-rest-3): dark purple bar, dark grey ink
    purple) printf 'foreground = "#4b4b5a"\nbackground = "#2b2542"\naccent = "#5a4b8a"\n' > "$ps/current/theme/colors.toml"
           printf '[bar]\nbackground = "#2b2542"\ntext = "#4b4b5a"\n[popups]\nbackground = "#2b2542"\ntext = "#4b4b5a"\n' > "$ps/current/theme/shell.toml"
           rm -f "$ps/current/theme/light.mode" ;;
  esac
  [ -f "$HOME/.local/state/omarchy/current/theme.name" ] && cp "$HOME/.local/state/omarchy/current/theme.name" "$ps/current/"
  # the wallpaper the owner has now, copied, so the bar's edge pixels blend against the same colours
  local bgf; bgf="$(readlink -f "$HOME/.local/state/omarchy/current/background" 2>/dev/null)"
  if [ -f "$bgf" ]; then mkdir -p "$ps/current/theme/backgrounds"; cp "$bgf" "$ps/current/theme/backgrounds/"; ln -sfn "$ps/current/theme/backgrounds/$(basename "$bgf")" "$ps/current/background"; fi
  [ -f "$HOME/.config/omarchy/shell.toml" ] && cp "$HOME/.config/omarchy/shell.toml" "$pc/shell.toml"
  # fonts only, as read-only links, so text metrics match the owner's
  [ -d "$HOME/.local/share/fonts" ] && ln -s "$HOME/.local/share/fonts" "$PHOME/.local/share/fonts"
  [ -d "$HOME/.config/fontconfig" ] && ln -s "$HOME/.config/fontconfig" "$PHOME/.config/fontconfig"
  # shell.json: the owner's bar settings; third-party plugin entries other than
  # Solfa are dropped (not installed here); Solfa points at the fake engine.
  python3 - "$HOME/.config/omarchy/shell.json" "$pc/shell.json" "$fake" <<'PY' || die "shell.json copy failed"
import json, os, sys
src, dst, fake = sys.argv[1:4]
cfg = json.load(open(src))
keep = lambda e: e.get("id", "").startswith("omarchy.") or e.get("id") == "io.github.sirallap.solfa"
bar = cfg.get("bar", {})
if os.environ.get("LAB_BAR", "owner") != "owner": bar["background"] = os.environ["LAB_BAR"]
for sec, items in list(bar.get("layout", {}).items()):
    bar["layout"][sec] = [e for e in items if keep(e)]
for e in bar["layout"].get("centerEnd", []):
    if e.get("id") == "io.github.sirallap.solfa":
        e["browser"] = fake; e["braveAdBlock"] = False; e["autostart"] = True
        e["eqEnabled"] = False; e["startPaused"] = False
out = {"version": 1, "bar": bar, "disabledPlugins": ["omarchy.dock", "omarchy.lock"],
       "dock": cfg.get("dock", {}), "plugins": []}
json.dump(out, open(dst, "w"), indent=2)
PY

  # -- Hyprland, headless, own config, no exec-once -----------------------------
  cat > "$LAB/hypr.lua" <<LUA
-- live-lab: one headless output, nothing else.
-- the host's real connector is visible to the DRM probe but never driven; park it
hl.monitor({ output = "DP-3", disabled = true })
hl.monitor({ output = "LAB-1", mode = "3840x2160@60", position = "0x0", scale = $SCALE })
hl.config({
  animations = { enabled = false },
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true, disable_watchdog_warning = true },
})
LUA
  echo "scale  : $SCALE  output 3840x2160"
  env -i PATH="$BASE_PATH" LANG="${LANG:-C.UTF-8}" HOME="$PHOME" XDG_CONFIG_HOME="$PHOME/.config" \
    XDG_STATE_HOME="$PHOME/.local/state" XDG_CACHE_HOME="$PHOME/.cache" XDG_DATA_HOME="$PHOME/.local/share" \
    XDG_RUNTIME_DIR="$RUN" HYPRLAND_HEADLESS_ONLY=1 LIBSEAT_BACKEND=noop XDG_SESSION_TYPE=wayland \
    Hyprland -c "$LAB/hypr.lua" >"$LAB/hyprland.log" 2>&1 &
  echo "hypr $!" >> "$PIDS"

  local i
  PSIG=""; PWDISP=""
  for i in $(seq 1 100); do
    PSIG="$(ls -1 "$RUN/hypr" 2>/dev/null | head -1)"
    PWDISP="$(cd "$RUN" && ls -1 wayland-* 2>/dev/null | grep -v '\.lock$' | head -1)"
    [ -n "$PSIG" ] && [ -n "$PWDISP" ] && [ -S "$RUN/$PWDISP" ] && [ -S "$RUN/hypr/$PSIG/.socket.sock" ] && break
    sleep 0.2
  done
  if [ -z "$PSIG" ] || [ -z "$PWDISP" ]; then tail -8 "$LAB/hyprland.log" >&2; cmd_stop; die "private Hyprland did not come up"; fi
  PWDISP="$RUN/$PWDISP"   # absolute, so it can never equal the live session's relative name
  printf "PSIG='%s'\nPWDISP='%s'\n" "$PSIG" "$PWDISP" > "$LAB/private.txt"
  load_private
  echo "private: sig=$PSIG display=$PWDISP runtime=$RUN"
  assert_private

  priv hyprctl output create headless LAB-1 >/dev/null 2>&1
  sleep 1
  priv hyprctl -j monitors | python3 -c "import sys,json;[print('monitor :',m['name'],m['width'],m['height'],'scale',m['scale']) for m in json.load(sys.stdin)]"

  # -- Solfa's bridge, started by hand: Service.qml would use systemd-run (and the
  # live unit's name); there is no session bus here, on purpose.
  local sr="$RUN/$PID_ID"; mkdir -p "$sr"
  bg bridge env SOLFA_RUNTIME_DIR="$sr" SOLFA_PROFILE_DIR="$LAB/solfa-profile" SOLFA_STATE_DIR="$LAB/solfa-state" \
    SOLFA_CACHE_DIR="$LAB/solfa-cache" SOLFA_BROWSER="$fake" SOLFA_LAUNCH_KEY="true|$fake|false" \
    SOLFA_ORPHAN_SECONDS=0 SOLFA_START_PAUSED=0 FAKE_PLAYER="${LAB_STATE:-playing}" /usr/bin/python3 "$pc/plugins/$PID_ID/bin/solfa-bridge"

  # -- the shell: the same command as the live session (omarchy-launch-shell) ---
  bg shell env QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 quickshell -n -p "$OMARCHY/shell"

  for i in $(seq 1 100); do
    priv hyprctl -j layers 2>/dev/null | grep -q 'omarchy-bar' && break; sleep 0.3
  done
  if [ "${OPEN:-1}" = 0 ]; then echo "started (panel not opened)"; return; fi
  for i in $(seq 1 60); do
    priv quickshell -p "$OMARCHY/shell" ipc call "$PID_ID" status >/dev/null 2>&1 && break; sleep 0.5
  done
  priv quickshell -p "$OMARCHY/shell" ipc call "$PID_ID" open >/dev/null 2>&1 || echo "warn: panel open call failed (see $LAB/shell.log)"
  sleep 2
  echo "started; logs in $LAB"
}

cmd_shot() {
  local label="${1:-}"; [ -n "$label" ] || die "usage: shot LABEL"
  load_private; assert_private
  mkdir -p "$OUTDIR"
  local stem="$OUTDIR/lab-$label"
  priv grim -o LAB-1 "$stem.png" || die "grim failed"
  python3 - "$stem" "${ZOOM:-8}" <<'PY' || die "could not locate the join in $stem.png"
# The panel is drawn inside the full-screen bar surface, so its edges are not a layer:
# find them in the pixels. Panel body = the longest uniform-colour run across several
# rows well below the bar; its top edge = first row (just inside the left edge) of that colour.
import sys
from collections import Counter
from PIL import Image
stem, zoom = sys.argv[1], int(sys.argv[2])
im = Image.open(stem + ".png").convert("RGB"); W, H = im.size; px = im.load()
near = lambda a, b, t=6: max(abs(a[i] - b[i]) for i in range(3)) <= t
def longest_run(y):
    best = (0, 0, 0)
    x = 0
    while x < W:
        seed = px[x, y]; e = x
        while e + 1 < W and near(px[e + 1, y], seed): e += 1
        if e - x > best[0]: best = (e - x, x, e)
        x = e + 1
    return best
rows = []
for y in range(160, 640, 8):
    n, l, r = longest_run(y)
    if n > 300: rows.append((l, r, px[l + 5, y]))
if not rows: sys.exit("no uniform panel body found (is the panel open?)")
L = Counter(r[0] for r in rows).most_common(1)[0][0]; R = Counter(r[1] for r in rows).most_common(1)[0][0]
col = next(r[2] for r in rows if r[0] == L)
top = next(y for y in range(H) if near(px[L + 30, y], col))
print("panel: x %d..%d (physical px), top edge y=%d, colour %s" % (L, R, top, col))
# The join the eye sees is where the Solfa pill (in the bar) widens, through concave
# fillets, into the panel's top edge: so the crops sit on the pill's left/right sides
# at that edge, taken on a row above the fillets (~28 physical px) so they are straight.
yr = max(0, top - 28)
xs = [x for x in range(L, R + 1) if near(px[x, yr], col, 8)]
if not xs: sys.exit("no pill found above the panel at row %d" % yr)
Lp, Rp = min(xs), max(xs)
print("pill : x %d..%d at row %d" % (Lp, Rp, yr))
def crop(name, cx):
    w, h = 56, 56
    x0, y0 = max(0, cx - w // 2), max(0, top - 40)
    out = "%s-%s.png" % (stem, name)
    im.crop((x0, y0, x0 + w, y0 + h)).resize((w * zoom, h * zoom), Image.NEAREST).save(out)
    print("crop :", out, "box", (x0, y0, x0 + w, y0 + h), "x%d" % zoom)
crop("join-left", Lp); crop("join-right", Rp + 1)
PY
}

cmd_engine_stop() { cmd_engine_op engine.stop; }
cmd_engine_start() { cmd_engine_op engine.start; }
cmd_engine_op() {  # a bridge op over its socket, as the panel's switch sends it (a fresh lab is "off" until the first start)
  load_private; assert_private
  python3 - "$RUN/$PID_ID/bridge.sock" "$1" <<'PY' || die "$1 failed"
import json, socket, sys, time
s = socket.socket(socket.AF_UNIX); s.settimeout(5); s.connect(sys.argv[1])
s.sendall((json.dumps({"id": 1, "op": sys.argv[2], "args": {}}) + "\n").encode())
time.sleep(1.5)
PY
  sleep 2
}

cmd_open() {  # open the panel (OPEN=0 start leaves it closed): the "open" half of a rest/open pair
  load_private; assert_private
  local i
  for i in $(seq 1 60); do   # the shell's ipc must answer first: an early call is dropped (a "missing" open in a sheet)
    priv quickshell -p "$OMARCHY/shell" ipc call "$PID_ID" status >/dev/null 2>&1 && break; sleep 0.5
  done
  priv quickshell -p "$OMARCHY/shell" ipc call "$PID_ID" "${1:-open}" >/dev/null 2>&1 || die "panel ${1:-open} failed"
  sleep 2
}

cmd_stop() {
  [ -s "$PIDS" ] || { echo "nothing to stop"; return; }
  local name pid
  # Only PIDs this script recorded, newest first (shell, bridge, then Hyprland).
  while read -r name pid; do
    [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null && kill -TERM "$pid" 2>/dev/null && echo "stopped $name $pid"
  done < <(tac "$PIDS")
  sleep 2
  while read -r name pid; do
    [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null && echo "killed $name $pid"
  done < "$PIDS"
  : > "$PIDS"
  [ -L "$RUN" ] && [ "$(readlink "$RUN")" = "$RUN_REAL" ] && rm -f "$RUN"
}

case "${1:-}" in
  start) shift; cmd_start "$@" ;;
  shot)  shift; cmd_shot "$@" ;;
  open)  shift; cmd_open "$@" ;;
  engine-stop) cmd_engine_stop ;;
  engine-start) cmd_engine_start ;;
  stop)  cmd_stop ;;
  *) echo "usage: $0 start [WORKTREE] | shot LABEL | open [close] | stop" >&2; exit 2 ;;
esac
