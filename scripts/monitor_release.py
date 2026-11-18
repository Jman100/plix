import time
import os
import sys
import hashlib
import urllib.request
import json

sys.path.insert(0, os.path.dirname(__file__))
import github_release as gr
import sync_release_checksums as src

def compute_sha256(url):
    print(f"Downloading for checksum: {url}", flush=True)
    req = urllib.request.Request(url, headers={"User-Agent": "Plix-Release-Verifier"})
    hasher = hashlib.sha256()
    with urllib.request.urlopen(req) as resp:
        while True:
            chunk = resp.read(65536)
            if not chunk:
                break
            hasher.update(chunk)
    return hasher.hexdigest().lower()

def monitor_and_sync(tag=None, timeout_seconds=1800):
    token = gr.get_github_token()
    if not token:
        print("No GitHub token found!", flush=True)
        sys.exit(1)

    manifest_path = os.path.join(os.path.dirname(__file__), '..', 'web_site', 'plix.json')
    if not os.path.exists(manifest_path):
        print(f"Error: {manifest_path} not found", file=sys.stderr)
        sys.exit(1)

    with open(manifest_path, 'r', encoding='utf-8') as f:
        manifest = json.load(f)

    if not tag:
        tag = f"v{manifest.get('version', '')}"

    print(f"=== Monitoring CI build workflows for {tag} ===", flush=True)
    start_time = time.time()

    required_assets = [
        "plix_android.apk",
        "plix_windows.exe",
        "plix_linux.deb",
        "plix_linux_arch.pkg.tar.zst",
        "plix_linux_portable.tar.gz",
    ]

    while time.time() - start_time < timeout_seconds:
        # Check assets on release
        try:
            release = gr.api_request(f'https://api.github.com/repos/{gr.REPO}/releases/tags/{tag}', token=token)
            assets = {a['name']: a for a in release.get('assets', [])}
            missing = [a for a in required_assets if a not in assets]
            
            if not missing:
                print(f"\nAll required release assets are present on {tag}!", flush=True)
                break
            else:
                elapsed = int(time.time() - start_time)
                print(f"[{elapsed}s elapsed] Waiting for assets to upload to {tag}: missing {missing}...", flush=True)
        except Exception as e:
            print(f"Warning checking release: {e}", flush=True)

        # Also check running workflows
        try:
            data = gr.api_request(f'https://api.github.com/repos/{gr.REPO}/actions/runs?per_page=12', token=token)
            for r in data.get('workflow_runs', []):
                if r.get('head_branch') == tag and r['name'] == 'Build Linux Packages (DEB, Arch Linux, Portable)':
                    if r['status'] == 'completed' and r['conclusion'] != 'success':
                        print(f"ERROR: Linux build workflow failed with conclusion: {r['conclusion']}", file=sys.stderr)
                        return False
        except Exception:
            pass

        time.sleep(20)

    if missing:
        print(f"Timed out waiting for required assets on {tag}: {missing}", file=sys.stderr)
        return False

    # Promote release to latest now that all assets are verified
    try:
        gr.set_release_latest(token, release['id'], "true")
        print(f"Successfully promoted {tag} to latest release!", flush=True)
    except Exception as e:
        print(f"Notice: Could not mark release as latest: {e}", file=sys.stderr)

    # Sync checksums
    print(f"\n=== Syncing verified checksums for {tag} ===", flush=True)
    success = src.sync_checksums(tag=tag, upload_release=True, commit_git=True)

    # Notify Discord
    try:
        import discord_changelog
        if discord_changelog.get_webhook_url():
            print("\nPosting updated changelog with verified Linux and Windows links to Discord...", flush=True)
            discord_changelog.post_changelog()
    except Exception as e:
        print(f"Notice: Could not post changelog to Discord: {e}", file=sys.stderr)

    return success

if __name__ == '__main__':
    tag_arg = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else None
    monitor_and_sync(tag=tag_arg)
