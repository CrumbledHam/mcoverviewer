# minecraft-overviewer-docker

A Docker image that runs [The Minecraft Overviewer](https://github.com/GregoryAM-SP/The-Minecraft-Overviewer) in a change-driven render loop and serves the resulting map via a built-in HTTP server.

Renders overworld, nether, and end dimensions. Detects player activity and re-renders automatically; falls back to a configurable maximum interval when the world is idle.

## Quick start

```bash
docker run -d \
  -v /path/to/your/world:/world:ro \
  -v /path/to/map/output:/output \
  -p 8080:8080 \
  ghcr.io/bugmancx/minecraft-overviewer
```

Map tiles are served at `http://localhost:8080`.

### docker-compose

A `docker-compose.yml` is included. Copy it alongside your world directory, adjust the volume paths, then:

```bash
docker compose up -d
```

The default compose file builds the image locally from the bundled `Dockerfile`. To use the pre-built image instead, replace `build: .` with `image: ghcr.io/bugmancx/minecraft-overviewer`.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `WORLD_PATH` | `/world` | Path to the Minecraft world directory (inside the container) |
| `OUTPUT_DIR` | `/output` | Root output directory; tiles are written to `$OUTPUT_DIR/$MAP_NAME` |
| `MAP_NAME` | `journey` | Sub-directory name used for output and the Overviewer world key |
| `MAX_ZOOM` | `8` | Maximum zoom level for all renders |
| `MAP_SIZE` | `0` | Square crop radius in blocks centred on 0,0. `0` = no crop |
| `UPDATE_INTERVAL` | `60` | Re-render even when idle, after this many **minutes**. `0` = only render on player activity |
| `CHECK_INTERVAL` | `60` | How often (in **seconds**) to poll for world changes |
| `TEXTURE_PATH` | _(bundled 1.21 jar)_ | Custom texture pack — URL, `.zip`, `.jar`, or extracted directory |
| `WEB_PORT` | `8080` | Port for the built-in map HTTP server |
| `POI_CONFIG_PATH` | `/config/pois.py` | Path to an Overviewer POI config snippet (optional) |

## Volumes

| Mount | Purpose |
|---|---|
| `/world` | Minecraft world directory (read-only recommended) |
| `/output` | Rendered map tiles and HTML |
| `/config` | Optional — drop a `pois.py` here for custom POI markers |
| `/textures` | Optional — used internally when `TEXTURE_PATH` is a URL |

## Ports

| Port | Purpose |
|---|---|
| `8080` | Built-in Python HTTP server serving the rendered map |

## Texture packs

`TEXTURE_PATH` accepts:

- **URL** (`https://…`) — downloaded at startup; `.zip` archives are extracted automatically
- **`.jar` / `.zip` file** — mounted into the container and used directly
- **Directory** — a pre-extracted resource pack with the standard `assets/` layout

The pack is validated for the presence of key 1.21 assets before use. If validation fails the bundled 1.21 client texture jar (downloaded at image build time) is used as a fallback.

## POI markers

Mount a file to `/config/pois.py` containing standard Overviewer `markers` / `filter` config. It is appended to the generated config at render time. Only `--genpoi --skip-scan --skip-players` is used to avoid bugs with older world formats.

## Render logic

1. On first start an immediate render is triggered.
2. Every `CHECK_INTERVAL` seconds the container checks `$WORLD_PATH/players/*.dat` modification times.
3. If any player file is newer than the last render timestamp, a re-render starts.
4. If no activity is detected but `UPDATE_INTERVAL` minutes have elapsed since the last render, a re-render starts anyway (unless `UPDATE_INTERVAL=0`).

## Building

```bash
docker build -t minecraft-overviewer ./build
```

The image pins Overviewer v1.21.0 and the matching Mojang 1.21 texture jar. To update, change the release URL and texture URL in the Dockerfile.
