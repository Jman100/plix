import os
import sys
import json
import hashlib
import urllib.request
import urllib.error
import subprocess

REPO = "Jman100/plix"

ASSET_MAP = {
    "plix_android.apk": "apkSha256",
    "plix_windows.exe": "windowsSha256",
    "plix_linux.deb": "linuxSha256",
    "plix_linux_arch.pkg.tar.zst": "linuxArchSha256",
    "plix_linux_portable.tar.gz": "linuxTarballSha256",
}

def get_github_token():
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        return token
    try:
        p = subprocess.Popen(['git', 'credential', 'fill'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        out, _ = p.communicate('protocol=https\nhost=github.com\npath=Jman100/plix.git\n\n')
        for line in out.strip().split('\n'):
            if line.startswith('password='):
                return line.split('=', 1)[1]
    except Exception:
        pass
    return None

def compute_url_sha256(url, token=None):
    headers = {"User-Agent": "Plix-Checksum-Sync"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    
    req = urllib.request.Request(url, headers=headers)
    hasher = hashlib.sha256()
    with urllib.request.urlopen(req) as resp:
        while True:
            chunk = resp.read(65536)
            if not chunk:
                break
            hasher.update(chunk)
    return hasher.hexdigest().lower()

def sync_checksums(tag=None, upload_release=True, commit_git=False):
    manifest_path = os.path.join(os.path.dirname(__file__), "..", "web_site", "plix.json")
    if not os.path.exists(manifest_path):
        print(f"Error: {manifest_path} not found", file=sys.stderr)
        return False

    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    if not tag:
        tag = f"v{manifest.get('version', '')}"
    
    print(f"=== Syncing Checksums for Release {tag} ===")
    token = get_github_token()
    
    # 1. Fetch release info from GitHub API
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "Plix-Checksum-Sync",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    
    api_url = f"https://api.github.com/repos/{REPO}/releases/tags/{tag}"
    req = urllib.request.Request(api_url, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            release_data = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"Error fetching release info for {tag}: {e}", file=sys.stderr)
        return False

    release_id = release_data.get("id")
    assets = {a["name"]: a for a in release_data.get("assets", [])}
    
    updated_count = 0
    for asset_name, key in ASSET_MAP.items():
        if asset_name in assets:
            download_url = assets[asset_name].get("browser_download_url")
            print(f"Fetching {asset_name} to compute SHA-256...")
            sha = compute_url_sha256(download_url)
            old_sha = manifest.get(key, "")
            print(f"  {asset_name}: {sha}")
            if old_sha != sha:
                print(f"  -> Updating {key}: {old_sha[:10]}... -> {sha[:10]}...")
                manifest[key] = sha
                updated_count += 1
            else:
                print(f"  -> Matches existing {key} ({sha[:10]}...)")
        else:
            print(f"Notice: {asset_name} not yet uploaded to release {tag}")

    # Write updated manifest
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=4)
    print(f"Updated {manifest_path} with verified checksums.")

    # Upload plix.json to GitHub Release if requested
    if upload_release and token and release_id:
        print(f"\nUploading verified plix.json to GitHub Release {tag}...")
        from github_release import upload_asset
        upload_asset(token, release_id, manifest_path, "plix.json")

    # Optionally commit and push to git
    if commit_git:
        try:
            subprocess.run(["git", "add", "web_site/plix.json"], check=True)
            diff_res = subprocess.run(["git", "diff", "--cached", "--quiet"])
            if diff_res.returncode != 0:
                print("Committing updated checksums to git...")
                subprocess.run(["git", "commit", "-m", f"chore(release): sync verified {tag} release checksums in plix.json"], check=True)
                subprocess.run(["git", "push", "origin", "main"], check=True)
                print("Pushed updated plix.json to main.")
            else:
                print("Git working tree clean, no commit needed.")
        except Exception as e:
            print(f"Warning: Failed to git commit/push: {e}", file=sys.stderr)

    return True

if __name__ == "__main__":
    tag_arg = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else None
    commit_flag = "--commit" in sys.argv
    sync_checksums(tag=tag_arg, upload_release=True, commit_git=commit_flag)
