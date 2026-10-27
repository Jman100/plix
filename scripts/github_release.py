import os
import sys
import json
import mimetypes
import subprocess
import urllib.request
import urllib.error

REPO = "Jman100/plix"

def get_github_token():
    # 1. Environment variable
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        return token
    # 2. Git credential helper
    try:
        p = subprocess.Popen(['git', 'credential', 'fill'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        out, _ = p.communicate('protocol=https\nhost=github.com\npath=Jman100/plix.git\n\n')
        for line in out.strip().split('\n'):
            if line.startswith('password='):
                return line.split('=', 1)[1]
    except Exception as e:
        print(f"Warning: Failed to get credentials from git helper: {e}", file=sys.stderr)
    return None

def api_request(url, method="GET", data=None, content_type="application/json", token=None):
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "Plix-Release-Tool",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if content_type:
        headers["Content-Type"] = content_type

    req_data = data
    if data is not None and content_type == "application/json" and not isinstance(data, bytes):
        req_data = json.dumps(data).encode("utf-8")

    req = urllib.request.Request(url, data=req_data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read()
            if body:
                return json.loads(body.decode("utf-8"))
            return None
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        print(f"API Error {e.code} for {method} {url}: {err_body}", file=sys.stderr)
        raise

def get_or_create_release(token, tag, title, body):
    # Check if release exists
    try:
        release = api_request(f"https://api.github.com/repos/{REPO}/releases/tags/{tag}", token=token)
        print(f"Release {tag} already exists (id: {release['id']}).")
        # Update body/title
        updated = api_request(
            f"https://api.github.com/repos/{REPO}/releases/{release['id']}",
            method="PATCH",
            data={"name": title, "body": body},
            token=token,
        )
        return updated
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise

    print(f"Creating new release {tag}...")
    return api_request(
        f"https://api.github.com/repos/{REPO}/releases",
        method="POST",
        data={
            "tag_name": tag,
            "name": title,
            "body": body,
            "draft": False,
            "prerelease": False,
        },
        token=token,
    )

def upload_asset(token, release_id, file_path, asset_name=None):
    if not asset_name:
        asset_name = os.path.basename(file_path)

    # 1. Check existing assets on release
    release = api_request(f"https://api.github.com/repos/{REPO}/releases/{release_id}", token=token)
    for asset in release.get("assets", []):
        if asset["name"] == asset_name:
            print(f"Deleting existing asset {asset_name} (id: {asset['id']})...")
            api_request(f"https://api.github.com/repos/{REPO}/releases/assets/{asset['id']}", method="DELETE", token=token)

    # 2. Upload new asset
    file_size = os.path.getsize(file_path)
    mime_type, _ = mimetypes.guess_type(file_path)
    if not mime_type:
        mime_type = "application/octet-stream"

    print(f"Uploading {asset_name} ({file_size} bytes, {mime_type})...")
    upload_url = f"https://uploads.github.com/repos/{REPO}/releases/{release_id}/assets?name={asset_name}"

    with open(file_path, "rb") as f:
        file_bytes = f.read()

    uploaded = api_request(
        upload_url,
        method="POST",
        data=file_bytes,
        content_type=mime_type,
        token=token,
    )
    print(f"Uploaded {asset_name} successfully! Download URL: {uploaded.get('browser_download_url')}")
    return uploaded

def main():
    if len(sys.argv) < 3:
        print("Usage: python github_release.py <tag> <title> [manifest_json_path] [files...]")
        sys.exit(1)

    tag = sys.argv[1]
    title = sys.argv[2]
    manifest_path = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3].endswith('.json') else None
    files_to_upload = sys.argv[4:] if manifest_path else sys.argv[3:]

    body = ""
    if manifest_path and os.path.exists(manifest_path):
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest_data = json.load(f)
            body = manifest_data.get("releaseNotes", "")

    token = get_github_token()
    if not token:
        print("Error: Could not retrieve GitHub token.", file=sys.stderr)
        sys.exit(1)

    release = get_or_create_release(token, tag, title, body)
    release_id = release["id"]

    for file_spec in files_to_upload:
        # file_spec can be "path" or "path:target_name"
        if ":" in file_spec and not file_spec.startswith("C:") and not file_spec.startswith("D:"):
            # check if it's path:name
            parts = file_spec.rsplit(":", 1)
            file_path, asset_name = parts[0], parts[1]
        else:
            file_path = file_spec
            asset_name = os.path.basename(file_path)

        if not os.path.exists(file_path):
            print(f"Warning: File not found: {file_path}", file=sys.stderr)
            continue

        upload_asset(token, release_id, file_path, asset_name)

    print("\nAll assets processed successfully for release", tag)

if __name__ == "__main__":
    main()
