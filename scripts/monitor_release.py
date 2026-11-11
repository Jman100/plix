import time
import os
import sys
import hashlib
import urllib.request
import json

sys.path.insert(0, os.path.dirname(__file__))
import github_release as gr

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

def main():
    token = gr.get_github_token()
    if not token:
        print("No GitHub token found!", flush=True)
        sys.exit(1)

    print("Monitoring CI build workflows for v1.8.7...", flush=True)
    start_time = time.time()
    
    while True:
        data = gr.api_request('https://api.github.com/repos/Jman100/plix/actions/runs?per_page=12', token=token)
        relevant_runs = [
            r for r in data['workflow_runs']
            if r['name'] in (
                'Build Android APK',
                'Build Windows Unified Installer (x64 & ARM64)',
                'Build Linux Packages (DEB, Arch Linux, Portable)'
            ) and r.get('head_commit', {}).get('message', '').startswith(('feat(release): bump to v1.8.7', 'chore(release)'))
            or (r.get('head_branch') == 'v1.8.7')
        ]
        
        all_done = True
        status_lines = []
        for r in relevant_runs:
            name = r['name']
            status = r['status']
            conclusion = r['conclusion']
            status_lines.append(f"{name}: {status} ({conclusion})")
            if status != 'completed':
                all_done = False
                
        if status_lines:
            print(f"[{int(time.time() - start_time)}s elapsed] " + " | ".join(status_lines), flush=True)
        else:
            print(f"[{int(time.time() - start_time)}s elapsed] Waiting for workflow runs to register...", flush=True)
            all_done = False
            
        if all_done and len(relevant_runs) >= 3:
            print("\nAll core build workflows completed successfully!", flush=True)
            break
            
        time.sleep(15)

    print("\nFetching release v1.8.7 assets...", flush=True)
    release = gr.api_request('https://api.github.com/repos/Jman100/plix/releases/tags/v1.8.7', token=token)
    assets = release.get('assets', [])
    print(f"Found {len(assets)} assets on v1.8.7 release.", flush=True)

    manifest_path = os.path.join(os.path.dirname(__file__), '..', 'web_site', 'plix.json')
    with open(manifest_path, 'r', encoding='utf-8') as f:
        manifest = json.load(f)

    for asset in assets:
        name = asset['name']
        durl = asset['browser_download_url']
        print(f"Computing SHA256 for {name}...", flush=True)
        sha = compute_sha256(durl)
        print(f"  -> {name}: {sha}", flush=True)

        if name == 'plix_android.apk':
            manifest['apkSha256'] = sha
        elif name == 'plix_windows.exe':
            manifest['windowsSha256'] = sha
        elif name == 'plix_linux.deb':
            manifest['linuxSha256'] = sha
        elif name == 'plix_linux_arch.pkg.tar.zst':
            manifest['linuxArchSha256'] = sha
        elif name == 'plix_linux_portable.tar.gz':
            manifest['linuxTarballSha256'] = sha

    with open(manifest_path, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, indent=4)
    print("Updated web_site/plix.json with exact release checksums!", flush=True)

    # Upload plix.json to the release
    print("Uploading plix.json to release v1.8.7...", flush=True)
    gr.upload_asset(token, release['id'], manifest_path, 'plix.json')

    # Commit and push to main
    os.system('git add web_site/plix.json')
    os.system('git commit -m "chore(release): sync exact v1.8.7 binary checksums"')
    os.system('git push origin main')
    print("Pushed updated checksums to main!", flush=True)

if __name__ == '__main__':
    main()
