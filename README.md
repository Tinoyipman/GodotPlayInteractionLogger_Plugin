# PlayerDataLogger

Records player interactions (clicks, drags, key presses) to a local CSV file and optionally syncs each row live to a Google Sheet via a Google Apps Script endpoint.

---

## What gets logged

Every entry captures:

| Column | Example | Description |
|---|---|---|
| Timestamp | `2025-05-26T14:32:01` | When the interaction happened |
| UserID | `USR-aB3kZqWx9R` | Persistent ID generated per device |
| GameVersion | `v1.0` | From your `_get_game_version()` override |
| Loop | `Loop 1` | From your `_get_loop_label()` override |
| Scene | `MainLevel` | Current scene name |
| Interaction | `Mouse Click` | Type of interaction |
| Object | `UI_StartButton` | What was interacted with |

Interaction types logged automatically:
- `Mouse Click`
- `Mouse Drag (Start)` / `Mouse Drag (End)`
- `Key Press` — Enter key only by default
- Any custom type via `PlayerDataLogger.log("type", "object")`

---

## Installation

1. Copy `PlayerDataLogger.gd` into your project (e.g. `res://autoloads/PlayerDataLogger.gd`).
2. Add it as an **Autoload** via **Project → Project Settings → Autoloads**:
   - **Path:** `res://autoloads/PlayerDataLogger.gd`
   - **Name:** `PlayerDataLogger`
3. Enable logging at runtime when you're ready to start recording (see below).

---

## Minimum Setup

```gdscript
# In any _ready() that runs at game start:
PlayerDataLogger.google_script_url = "https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec"
PlayerDataLogger.set_logging_enabled(true)
```

Leave `google_script_url` empty (`""`) to record to local CSV only — no Google Sheets required.

---

## Google Sheets Setup

To sync data to a Google Sheet in real time:

### 1. Create the Sheet

1. Go to [Google Sheets](https://sheets.google.com) and create a new spreadsheet.
2. In the first row, add your column headers in order:
   ```
   Timestamp | UserID | GameVersion | Loop | Scene | Interaction | Object
   ```

### 2. Create the Apps Script

1. In your Sheet, open **Extensions → Apps Script**.
2. Replace the default code with:

```javascript
function doPost(e) {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  var data = JSON.parse(e.postData.contents);
  sheet.appendRow(data.row_data);
  return ContentService.createTextOutput("OK");
}
```

3. Click **Save** (name the project anything you like).

### 3. Deploy as a Web App

1. Click **Deploy → New deployment**.
2. Click the gear icon next to **Type** and select **Web app**.
3. Set:
   - **Execute as:** Me
   - **Who has access:** Anyone
4. Click **Deploy** and copy the Web App URL.
5. Paste it into `PlayerDataLogger.google_script_url`.

> ⚠️ Anyone with the URL can append rows to your sheet. Treat it like a password — don't commit it to version control. Load it at runtime from a config file if needed.

---

## Configuration Reference

All properties can be set in the Inspector (if used as a scene node) or from code.

| Property | Default | Description |
|---|---|---|
| `google_script_url` | `""` | Apps Script URL. Empty = local only |
| `log_file_path` | `user://playtest_log.csv` | Local CSV backup location |
| `id_file_path` | `user://user_id.txt` | Where the persistent user ID is stored |
| `drag_threshold` | `10.0` | Pixels before a press becomes a drag |
| `csv_headers` | *(see script)* | Column headers written to the CSV |
| `interaction_area_node_name` | `"InteractionArea"` | Name of your transparent click-target nodes |
| `http_timeout` | `15.0` | Seconds before a cloud sync request times out |
| `http_max_redirects` | `10` | Max redirects (Google redirects once by default) |

---

## Enabling & Disabling

Logging is **off by default**. Turn it on when appropriate — for example, only during playtests, or only after the player accepts a data collection notice:

```gdscript
# Enable
PlayerDataLogger.set_logging_enabled(true)

# Disable (e.g. on pause screen or main menu)
PlayerDataLogger.set_logging_enabled(false)
```

---

## Logging Custom Interactions

Automatic input detection covers mouse and Enter key. For anything else — button presses, inventory actions, scene transitions — call `log()` directly:

```gdscript
# Simple
PlayerDataLogger.log("Item Collected", "HealthPotion")

# From a button's pressed signal
func _on_start_button_pressed():
    PlayerDataLogger.log("Button Press", "StartButton")
    load_game()
```

---

## Connecting to Your Game Systems

The logger has two virtual methods you can override to pull in project-specific data.

### Option A — Subclass (recommended)

```gdscript
# res://autoloads/MyDataLogger.gd
extends PlayerDataLogger

func _get_game_version() -> String:
    return "v" + str(GameVersionManager.get_version())

func _get_loop_label() -> String:
    return "Loop " + str(GameFlowManager.get_loop_count() + 1)
```

Register `MyDataLogger.gd` as the Autoload instead of `PlayerDataLogger.gd`, keeping the name `PlayerDataLogger` so the rest of your code needs no changes.

### Option B — Set plain strings at startup

```gdscript
# If you just want static values for a specific playtest build:
func _ready():
    PlayerDataLogger.google_script_url = "https://..."
    PlayerDataLogger.set_logging_enabled(true)
```

The default `_get_game_version()` returns `"v1.0"` and `_get_loop_label()` returns `"Loop 1"` if you don't override them.

---

## InteractionArea Convention

The logger resolves which game object was clicked using physics queries. It handles a common pattern where a dedicated `Area2D` (or `CollisionShape2D`) acts as a click-target:

```
MyObject          ← logged name
└── InteractionArea   ← physics collider the query hits
```

If your project uses a different node name, change the export:

```gdscript
PlayerDataLogger.interaction_area_node_name = "Hitbox"
```

For a completely different scene structure, override `_resolve_object_name()`:

```gdscript
func _resolve_object_name(collider: Node) -> String:
    # Your custom logic here
    return collider.get_parent().name
```

---

## Local CSV Backup

Every entry is written to `user://playtest_log.csv` before the cloud sync attempt, so data is never lost if the network is unavailable. You can find this file at:

| Platform | Path |
|---|---|
| Windows | `%APPDATA%\Godot\app_userdata\<ProjectName>\` |
| macOS | `~/Library/Application Support/Godot/app_userdata/<ProjectName>/` |
| Linux | `~/.local/share/godot/app_userdata/<ProjectName>/` |

---

## User ID

A random 10-character ID (e.g. `USR-aB3kZqWx9R`) is generated the first time the logger runs on a device and saved to `user://user_id.txt`. It persists across sessions so you can track a single tester's journey over multiple runs.

```gdscript
# Read it if you need it elsewhere:
var uid = PlayerDataLogger.get_user_id()
```
