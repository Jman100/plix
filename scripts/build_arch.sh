#!/bin/bash
set -e

VERSION="${1:-1.5.1}"
ARCH="x86_64"
DIST_DIR="dist/plix-arch"
STAGE_DIR="build/staged_linux"

echo "=== Packaging Plix Arch Linux (.pkg.tar.zst) and Standalone Tarball v${VERSION} (${ARCH}) ==="

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}/usr/bin"
mkdir -p "${DIST_DIR}/usr/lib/plix"
mkdir -p "${DIST_DIR}/usr/share/applications"
mkdir -p "${DIST_DIR}/usr/share/pixmaps"
mkdir -p "${DIST_DIR}/usr/share/icons/hicolor/512x512/apps"
mkdir -p "${STAGE_DIR}"

# Copy release bundle
if [ -d "build/linux/x64/release/bundle" ]; then
  cp -r build/linux/x64/release/bundle/* "${DIST_DIR}/usr/lib/plix/"
else
  echo "Error: build/linux/x64/release/bundle not found. Did flutter build linux --release run?"
  exit 1
fi

# Launcher wrapper
cat << 'EOF' > "${DIST_DIR}/usr/bin/plix"
#!/bin/bash
exec /usr/lib/plix/plix "$@"
EOF

# Ensure proper permissions across bundle
chmod -R u+rwX,go+rX,go-w "${DIST_DIR}"
chmod 755 "${DIST_DIR}/usr/bin/plix"
chmod 755 "${DIST_DIR}/usr/lib/plix/plix"
if [ -d "${DIST_DIR}/usr/lib/plix/lib" ]; then
  find "${DIST_DIR}/usr/lib/plix/lib" -type f -name "*.so*" -exec chmod 755 {} +
fi

# Desktop Entry
cat << 'EOF' > "${DIST_DIR}/usr/share/applications/plix.desktop"
[Desktop Entry]
Name=Plix
Comment=Modern Streaming Client for Plex & Jellyfin
Exec=/usr/bin/plix %u
Icon=plix
Terminal=false
Type=Application
Categories=AudioVideo;Video;Player;
Keywords=Plex;Jellyfin;Streaming;Media;Player;
EOF

# App icon
if [ -f "web_site/app_icon.png" ]; then
  cp "web_site/app_icon.png" "${DIST_DIR}/usr/share/pixmaps/plix.png"
  cp "web_site/app_icon.png" "${DIST_DIR}/usr/share/icons/hicolor/512x512/apps/plix.png"
fi

# Calculate installed size in bytes
INSTALLED_SIZE=$(du -sb "${DIST_DIR}/usr" | cut -f1)
BUILD_DATE=$(date +%s)

# Generate Arch .PKGINFO
cat << EOF > "${DIST_DIR}/.PKGINFO"
pkgname = plix-bin
pkgbase = plix-bin
pkgver = ${VERSION}-1
pkgdesc = Modern Streaming Client for Plex & Jellyfin
url = https://plix.jman100.com
builddate = ${BUILD_DATE}
packager = Plix Team <support@plix.tv>
size = ${INSTALLED_SIZE}
arch = x86_64
license = MIT
depend = gtk3
depend = mpv
depend = libepoxy
depend = hicolor-icon-theme
provides = plix
conflict = plix
EOF

# Create .BUILDINFO (standard Arch metadata)
cat << EOF > "${DIST_DIR}/.BUILDINFO"
format = 2
pkgname = plix-bin
pkgver = ${VERSION}-1
pkgarch = x86_64
pkgbuild_sha256sum = 0000000000000000000000000000000000000000000000000000000000000000
packager = Plix Team <support@plix.tv>
builddate = ${BUILD_DATE}
buildenv = !distcc !color !ccache check !sign
installed = coreutils
EOF

# Package Arch package using tar + zstd
PKG_FILE="${STAGE_DIR}/plix-${VERSION}-1-x86_64.pkg.tar.zst"
echo "Creating Arch Linux package: ${PKG_FILE}"
(cd "${DIST_DIR}" && tar -cf - .PKGINFO .BUILDINFO usr | zstd -c -T0 -19 > "../../${PKG_FILE}")
cp "${PKG_FILE}" "${STAGE_DIR}/plix_linux_arch.pkg.tar.zst"
echo "Successfully created ${PKG_FILE} and plix_linux_arch.pkg.tar.zst"

# Also create portable standalone tar.gz bundle
TARBALL_DIR="dist/plix-${VERSION}-linux-x86_64"
rm -rf "${TARBALL_DIR}"
mkdir -p "${TARBALL_DIR}"
cp -r build/linux/x64/release/bundle/* "${TARBALL_DIR}/"
cp "${DIST_DIR}/usr/share/applications/plix.desktop" "${TARBALL_DIR}/"
if [ -f "web_site/app_icon.png" ]; then
  cp "web_site/app_icon.png" "${TARBALL_DIR}/plix.png"
fi

cat << 'EOF' > "${TARBALL_DIR}/run.sh"
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/plix" "$@"
EOF
chmod +x "${TARBALL_DIR}/run.sh"
chmod +x "${TARBALL_DIR}/plix"

TAR_FILE="${STAGE_DIR}/plix-${VERSION}-linux-x86_64.tar.gz"
echo "Creating portable tarball: ${TAR_FILE}"
tar -czf "${TAR_FILE}" -C "dist" "plix-${VERSION}-linux-x86_64"
cp "${TAR_FILE}" "${STAGE_DIR}/plix_linux_portable.tar.gz"
echo "Successfully created ${TAR_FILE} and plix_linux_portable.tar.gz"

ls -lh "${STAGE_DIR}"
