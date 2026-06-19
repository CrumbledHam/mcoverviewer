#!/usr/bin/env bash
# Render loop for Minecraft Overviewer.
# Watches the world for player activity and re-renders on change,
# with a configurable maximum interval for idle worlds.
# Also starts a Python HTTP server to serve the finished map.
set -euo pipefail

# ── Configuration (all overridable via environment) ──────────────────────────
WORLD_PATH="${WORLD_PATH:-/world}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
MAP_NAME="${MAP_NAME:-world}"
TEXTURE_PATH="${TEXTURE_PATH:-}"
UPDATE_INTERVAL="${UPDATE_INTERVAL:-60}"   # minutes between forced re-renders (0 = disabled)
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"     # seconds between change-detection polls
MAX_ZOOM="${MAX_ZOOM:-8}"
WEB_PORT="${WEB_PORT:-8080}"
MAP_SIZE="${MAP_SIZE:-0}"                  # square crop radius in blocks; 0 = no crop
POI_CONFIG_PATH="${POI_CONFIG_PATH:-/config/pois.py}"

# ── Sanity checks ─────────────────────────────────────────────────────────────
if [ ! -d "$WORLD_PATH" ]; then
  echo "World path '$WORLD_PATH' does not exist or is not a directory" >&2
  exit 1
fi

OUT_DIR="$OUTPUT_DIR/$MAP_NAME"
mkdir -p "$OUT_DIR"

# ── Texture resolution ────────────────────────────────────────────────────────
# Priority: TEXTURE_PATH (URL → download; file/dir → use directly)
#           → bundled 1.21 jar baked into the image at build time
RESOLVED_TEXTURE_PATH=""
DEFAULT_TEXTURE_JAR="/opt/minecraft-textures/1.21.jar"

# Validate that a texture pack contains the key 1.21 assets Overviewer needs.
# Returns 0 if valid, 1 if the required files are missing.
validate_texturepack() {
  local path="$1"

  if [ -d "$path" ]; then
    if [ -f "$path/assets/minecraft/textures/block/grass_block_top.png" ] && \
       [ -f "$path/assets/minecraft/textures/colormap/foliage.png" ] && \
       [ -f "$path/assets/minecraft/textures/colormap/grass.png" ]; then
      return 0
    fi
    echo "Texture pack at '$path' does not contain required 1.21 assets; falling back to default client textures." >&2
    return 1
  fi

  if [[ "$path" == *.jar || "$path" == *.zip ]]; then
    if unzip -l "$path" 'assets/minecraft/textures/block/grass_block_top.png' 2>/dev/null | grep -q 'grass_block_top.png' && \
       unzip -l "$path" 'assets/minecraft/textures/colormap/foliage.png' 2>/dev/null | grep -q 'foliage.png' && \
       unzip -l "$path" 'assets/minecraft/textures/colormap/grass.png' 2>/dev/null | grep -q 'grass.png'; then
      return 0
    fi
    echo "Texture pack archive '$path' does not contain required 1.21 assets; falling back to default client textures." >&2
    return 1
  fi

  # Unknown type — pass through and let Overviewer complain if needed
  return 0
}

if [ -n "$TEXTURE_PATH" ]; then
  if [[ "$TEXTURE_PATH" =~ ^https?:// ]]; then
    # URL: download to /textures; extract zip archives in-place
    url="$TEXTURE_PATH"
    base="$(basename "$url")"
    tex_root="/textures"
    mkdir -p "$tex_root"
    target="$tex_root/$base"

    echo "Downloading texture pack from $url to $target..."
    wget -O "$target" "$url"

    case "$target" in
      *.zip)
        if ! unzip -tq "$target" >/dev/null; then
          echo "Texture zip '$target' failed integrity check" >&2
          exit 1
        fi
        dest_dir="${target%.zip}"
        mkdir -p "$dest_dir"
        unzip -oq "$target" -d "$dest_dir"
        RESOLVED_TEXTURE_PATH="$dest_dir"
        ;;
      *.jar)
        if ! unzip -tq "$target" >/dev/null; then
          echo "Texture jar '$target' failed integrity check" >&2
          exit 1
        fi
        RESOLVED_TEXTURE_PATH="$target"
        ;;
      *)
        RESOLVED_TEXTURE_PATH="$target"
        ;;
    esac
  elif [ -d "$TEXTURE_PATH" ] || [ -f "$TEXTURE_PATH" ]; then
    RESOLVED_TEXTURE_PATH="$TEXTURE_PATH"
  else
    echo "Warning: TEXTURE_PATH '$TEXTURE_PATH' not found and is not a URL; textures will fallback to defaults if available." >&2
  fi
fi

if [ -n "$RESOLVED_TEXTURE_PATH" ]; then
  if ! validate_texturepack "$RESOLVED_TEXTURE_PATH"; then
    RESOLVED_TEXTURE_PATH=""
  fi
fi

# Use the custom pack if resolved, otherwise fall back to the bundled jar
EFFECTIVE_TEXTURE_PATH="$RESOLVED_TEXTURE_PATH"
if [ -z "$EFFECTIVE_TEXTURE_PATH" ] && [ -f "$DEFAULT_TEXTURE_JAR" ]; then
  EFFECTIVE_TEXTURE_PATH="$DEFAULT_TEXTURE_JAR"
fi

# ── Overviewer binary detection ───────────────────────────────────────────────
# The binary name differs between release versions
if command -v overviewer.py >/dev/null 2>&1; then
  OVERVIEWER_CMD="overviewer.py"
elif command -v overviewer >/dev/null 2>&1; then
  OVERVIEWER_CMD="overviewer"
else
  echo "Minecraft Overviewer executable not found in PATH" >&2
  exit 1
fi

# ── Config generation ─────────────────────────────────────────────────────────
# Build the Overviewer Python config at runtime so environment variables
# (world path, output dir, zoom, crop) are reflected without a rebuild.
CONFIG_FILE="/tmp/overviewer_config.py"

# Optional square crop centred on 0,0; omitted entirely when MAP_SIZE <= 0
CROP_CONFIG_LINE=""
if [[ "$MAP_SIZE" =~ ^[0-9]+$ ]] && [ "$MAP_SIZE" -gt 0 ]; then
  HALF_SIZE=$((MAP_SIZE / 2))
  CROP_CONFIG_LINE="  \"crop\": (-$HALF_SIZE, -$HALF_SIZE, $HALF_SIZE, $HALF_SIZE),"
fi

cat >"$CONFIG_FILE" <<EOF
worlds["$MAP_NAME"] = "$WORLD_PATH"

renders["${MAP_NAME}_overworld"] = {
  "world": "$MAP_NAME",
  "title": "$MAP_NAME (Overworld)",
  "rendermode": "normal",
  "dimension": "overworld",
${CROP_CONFIG_LINE}
  "maxzoom": $MAX_ZOOM,
}

renders["${MAP_NAME}_nether"] = {
  "world": "$MAP_NAME",
  "title": "$MAP_NAME (Nether)",
  "rendermode": "nether",
  "dimension": "nether",
${CROP_CONFIG_LINE}
  "maxzoom": $MAX_ZOOM,
}

renders["${MAP_NAME}_end"] = {
  "world": "$MAP_NAME",
  "title": "$MAP_NAME (The End)",
  "rendermode": "normal",
  "dimension": "end",
${CROP_CONFIG_LINE}
  "maxzoom": $MAX_ZOOM,
}

outputdir = "$OUT_DIR"
EOF

if [ -n "$EFFECTIVE_TEXTURE_PATH" ]; then
  cat >>"$CONFIG_FILE" <<EOF
texturepath = "$EFFECTIVE_TEXTURE_PATH"
EOF
fi

# Append POI marker definitions if a config file is mounted
if [ -f "$POI_CONFIG_PATH" ]; then
  echo "Including POI config from $POI_CONFIG_PATH"
  cat "$POI_CONFIG_PATH" >>"$CONFIG_FILE"
fi

# ── Startup summary ───────────────────────────────────────────────────────────
echo "Running Minecraft Overviewer (change-driven renders)..."
echo "  World:    $WORLD_PATH"
echo "  Output:   $OUT_DIR"
if [ -n "$EFFECTIVE_TEXTURE_PATH" ]; then
  echo "  Textures: $EFFECTIVE_TEXTURE_PATH"
fi
echo "Using generated config at $CONFIG_FILE"

# ── HTTP server ───────────────────────────────────────────────────────────────
# Serve the output directory so the map is browsable immediately.
# Runs in the background; the render loop is the foreground process.
echo "Starting web server on port $WEB_PORT serving $OUT_DIR"
( cd "$OUT_DIR" && python3 -m http.server "$WEB_PORT" ) &

# ── Render loop ───────────────────────────────────────────────────────────────
# Triggers a render when:
#   1. No render has ever run (first start)
#   2. A player .dat file is newer than the last render timestamp
#   3. UPDATE_INTERVAL minutes have elapsed since the last render (idle fallback)
LAST_RENDER_FILE="/tmp/.overviewer_last_render"

echo "Checking for region file changes every ${CHECK_INTERVAL}s (max re-render interval: ${UPDATE_INTERVAL}m)"

while true; do
  needs_render=0
  render_reason=""

  if [ ! -f "$LAST_RENDER_FILE" ]; then
    needs_render=1
    render_reason="initial render"
  else
    if find "$WORLD_PATH/players" -name "*.dat" -newer "$LAST_RENDER_FILE" -print -quit 2>/dev/null | grep -q .; then
      needs_render=1
      render_reason="player activity detected"
    elif [ "$UPDATE_INTERVAL" -gt 0 ]; then
      last_epoch=$(stat -c %Y "$LAST_RENDER_FILE" 2>/dev/null || echo 0)
      age=$(( $(date +%s) - last_epoch ))
      if [ "$age" -ge "$((UPDATE_INTERVAL * 60))" ]; then
        needs_render=1
        render_reason="max interval (${UPDATE_INTERVAL}m) exceeded"
      fi
    fi
  fi

  if [ "$needs_render" -eq 1 ]; then
    echo "Starting Overviewer render at $(date) — ${render_reason}"
    if [ -f "$POI_CONFIG_PATH" ]; then
      # --skip-scan and --skip-players avoid genPOI bugs on older world formats
      # and keep POI generation fast by only processing the manually defined markers.
      "$OVERVIEWER_CMD" --config="$CONFIG_FILE" --genpoi --skip-scan --skip-players || echo "POI generation failed (genpoi)" >&2
    fi
    "$OVERVIEWER_CMD" --config="$CONFIG_FILE"
    touch "$LAST_RENDER_FILE"
    echo "Overviewer render complete at $(date)"
  fi

  sleep "$CHECK_INTERVAL"
done
