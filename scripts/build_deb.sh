#!/bin/bash
set -e

VERSION="${1:-1.5.1}"
ARCH="amd64"
DIST_DIR="dist/plix_${VERSION}_${ARCH}"

echo "=== Packaging Plix Debian (.deb) package v${VERSION} (${ARCH}) ==="

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}/DEBIAN"
mkdir -p "${DIST_DIR}/usr/bin"
mkdir -p "${DIST_DIR}/usr/lib/plix"
mkdir -p "${DIST_DIR}/usr/share/applications"
mkdir -p "${DIST_DIR}/usr/share/pixmaps"
mkdir -p "${DIST_DIR}/usr/share/icons/hicolor/512x512/apps"

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

# Control File
cat << EOF > "${DIST_DIR}/DEBIAN/control"
Package: plix
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: Plix Team <support@plix.tv>
Depends: libc6, libgtk-3-0, libmpv1 | libmpv2 | libmpv-dev, libepoxy0
Section: video
Priority: optional
Homepage: https://plix.jman100.com
Description: Plix - Modern Streaming Client for Plex & Jellyfin
 A beautifully crafted, modern streaming client for Plex and Jellyfin servers.
EOF

# Build package
mkdir -p build/staged_linux
dpkg-deb --build --root-owner-group "${DIST_DIR}" build/staged_linux/plix_linux.deb
echo "Successfully built build/staged_linux/plix_linux.deb"
