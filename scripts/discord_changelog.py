import os
import sys
import json
import urllib.request
import urllib.error
from datetime import datetime, timezone

WEBHOOK_FILE = os.path.join(os.path.dirname(__file__), "..", ".discord_webhook")
LAST_MSG_FILE = os.path.join(os.path.dirname(__file__), "..", ".discord_last_message_id")
MANIFEST_FILE = os.path.join(os.path.dirname(__file__), "..", "web_site", "plix.json")

def get_webhook_url():
    # 1. Environment variable
    url = os.environ.get("DISCORD_WEBHOOK_URL")
    if url and url.strip():
        return url.strip()
    # 2. Local gitignored file
    if os.path.exists(WEBHOOK_FILE):
        try:
            with open(WEBHOOK_FILE, "r", encoding="utf-8") as f:
                content = f.read().strip()
                if content:
                    return content
        except Exception:
            pass
    return None

def get_last_message_id():
    if os.path.exists(LAST_MSG_FILE):
        try:
            with open(LAST_MSG_FILE, "r", encoding="utf-8") as f:
                content = f.read().strip()
                if content:
                    return content
        except Exception:
            pass
    return None

def save_last_message_id(msg_id):
    try:
        with open(LAST_MSG_FILE, "w", encoding="utf-8") as f:
            f.write(str(msg_id).strip())
    except Exception as e:
        print(f"Warning: Failed to save last message ID: {e}", file=sys.stderr)

def delete_previous_message(webhook_url, msg_id):
    if not msg_id:
        return
    # Base webhook url without query parameters
    base_url = webhook_url.split("?")[0].rstrip("/")
    delete_url = f"{base_url}/messages/{msg_id}"
    req = urllib.request.Request(
        delete_url,
        headers={"User-Agent": "Plix-Changelog-Bot/1.0"},
        method="DELETE"
    )
    try:
        with urllib.request.urlopen(req) as resp:
            print(f"Successfully deleted previous changelog message (ID: {msg_id}).")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print(f"Previous message (ID: {msg_id}) not found or already deleted.")
        else:
            print(f"Warning: Failed to delete previous message {msg_id}: HTTP {e.code}", file=sys.stderr)
    except Exception as e:
        print(f"Warning: Could not delete previous message: {e}", file=sys.stderr)

def build_embed(manifest_data):
    version = manifest_data.get("version", "1.0.0")
    version_code = manifest_data.get("versionCode", 1)
    release_date = manifest_data.get("releaseDate", datetime.now().strftime("%Y-%m-%d"))
    raw_notes = manifest_data.get("releaseNotes", "No changelog provided.")

    # Format release notes into bullet points if not already
    lines = raw_notes.strip().split("\n")
    formatted_notes = []
    for line in lines:
        l = line.strip()
        if not l:
            continue
        if not (l.startswith("-") or l.startswith("•") or l.startswith("*")):
            formatted_notes.append(f"• {l}")
        else:
            # Normalize to clean bullet
            content = l.lstrip("-*• ").strip()
            formatted_notes.append(f"• {content}")
    notes_str = "\n".join(formatted_notes)

    # Direct links
    apk_url = manifest_data.get("apkUrl", "https://github.com/Jman100/plix/releases/latest/download/plix_android.apk")
    win_url = manifest_data.get("windowsUrl", "https://github.com/Jman100/plix/releases/latest/download/plix_windows.exe")
    release_page = f"https://github.com/Jman100/plix/releases/tag/v{version}"

    embed = {
        "title": f"🚀 Plix v{version} Released",
        "url": release_page,
        "description": f"**Changelog:**\n{notes_str}",
        "color": 0x00D2C4, # Plix Arctic Frost / Cyan
        "fields": [
            {
                "name": "📌 Version",
                "value": f"`v{version}` (Build {version_code})",
                "inline": True
            },
            {
                "name": "📅 Build Date",
                "value": f"`{release_date}`",
                "inline": True
            },
            {
                "name": "📦 Downloads",
                "value": f"[Android APK]({apk_url}) • [Windows Installer]({win_url}) • [GitHub Release]({release_page})",
                "inline": False
            }
        ],
        "footer": {
            "text": "Plix Media Center • Updates",
            "icon_url": "https://raw.githubusercontent.com/Jman100/plix/main/web_site/app_icon.png"
        },
        "timestamp": datetime.now(timezone.utc).isoformat()
    }
    return embed

def post_changelog(webhook_url=None, manifest_path=None):
    if not webhook_url:
        webhook_url = get_webhook_url()
    if not webhook_url:
        print("Error: Discord webhook URL not found in environment or .discord_webhook.", file=sys.stderr)
        sys.exit(1)

    if not manifest_path:
        manifest_path = MANIFEST_FILE

    if not os.path.exists(manifest_path):
        print(f"Error: Manifest file {manifest_path} not found.", file=sys.stderr)
        sys.exit(1)

    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest_data = json.load(f)

    # 1. Delete previous message if one exists
    last_msg_id = get_last_message_id()
    if last_msg_id:
        delete_previous_message(webhook_url, last_msg_id)

    # 2. Build payload
    embed = build_embed(manifest_data)
    payload = {
        "username": "Plix Updates",
        "avatar_url": "https://raw.githubusercontent.com/Jman100/plix/main/web_site/app_icon.png",
        "embeds": [embed]
    }

    # 3. Post to webhook with wait=true so Discord returns message details
    base_url = webhook_url.split("?")[0].rstrip("/")
    post_url = f"{base_url}?wait=true"

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        post_url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "Plix-Changelog-Bot/1.0"
        },
        method="POST"
    )

    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode("utf-8")
            res_json = json.loads(body)
            new_msg_id = res_json.get("id")
            if new_msg_id:
                save_last_message_id(new_msg_id)
                print(f"Successfully posted changelog to Discord! Message ID: {new_msg_id}")
            else:
                print("Posted to Discord, but no message ID returned in response.")
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode("utf-8", errors="replace")
        print(f"Discord API Error {e.code}: {err_msg}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error posting changelog to Discord: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    post_changelog()
