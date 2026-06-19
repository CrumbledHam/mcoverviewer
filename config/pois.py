import json
import os

# Reads POI data from pois.json and attaches markers to the overworld render.
# This file is appended to the generated Overviewer config at render time.
# Edit pois.json to add/move markers — do not hardcode coordinates here.

DATA_PATH = os.environ.get("POI_DATA_PATH", "/config/pois.json")

try:
    with open(DATA_PATH, "r", encoding="utf-8") as f:
        _data = json.load(f)
except Exception:
    _data = {}

_pois = _data.get("pois", [])
_groups = _data.get("groups", [])

_map_name = os.environ.get("MAP_NAME", "world")
target_render = None
try:
    target_render = renders.get(f"{_map_name}_overworld")
except Exception:
    target_render = None

if isinstance(target_render, dict):
    if _pois:
        target_render["manualpois"] = _pois

    if _groups:
        def _make_filter(match_id=None, match_all=False):
            def _filter(poi):
                if match_all or (match_id is not None and poi.get("id") == match_id):
                    name = poi.get("name", "")
                    desc = poi.get("description")
                    if desc:
                        return (name, desc)
                    return name
            return _filter

        marker_entries = []
        for grp in _groups:
            match_all = bool(grp.get("match_all"))
            match_id = grp.get("match_id") or grp.get("id")
            if not match_all and not match_id:
                continue

            entry = dict(
                name=grp.get("name", match_id),
                filterFunction=_make_filter(match_id=match_id, match_all=match_all),
            )
            if grp.get("icon"):
                entry["icon"] = grp["icon"]
            if "checked" in grp:
                entry["checked"] = bool(grp["checked"])
            marker_entries.append(entry)

        if marker_entries:
            target_render["markers"] = marker_entries
