# YouTube Music in the i3 bar: polybar pill, player popup and the mpv service.
pkgname=ytm-bar-git
pkgver=r0
pkgrel=1
pkgdesc="YouTube Music for i3 and polybar: now-playing pill, player popup, mpv + yt-dlp"
arch=(any)
url="https://github.com/crsstha/ytm-bar"
license=(MIT)
depends=(python mpv yt-dlp python-ytmusicapi python-gobject python-cairo webkit2gtk-4.1)
makedepends=(git)
optdepends=('polybar: the bar pill'
            'mpv-mpris: MPRIS control (playerctl, media keys)'
            'libnotify: song notifications'
            'chromium: Sign in with Google'
            'kitty: Open in TUI (or alacritty)')
provides=(ytm-bar)
conflicts=(ytm-bar)
source=("$pkgname::git+$url.git#branch=arch")
sha256sums=(SKIP)

pkgver() {
  cd "$pkgname"
  printf "r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

package() {
  cd "$pkgname"
  local lib=/usr/lib/ytm-bar
  install -d "$pkgdir$lib" "$pkgdir/usr/bin"
  cp -r bin i3 fonts "$pkgdir$lib/"
  for cmd in bin/ytm-bar bin/ytm-tui i3/ytm-panel; do
    ln -s "$lib/$cmd" "$pkgdir/usr/bin/${cmd##*/}"
  done
  sed 's|%h/.local/bin/ytm-bar|/usr/bin/ytm-bar|' systemd/ytm-bar.service \
    | install -Dm644 /dev/stdin "$pkgdir/usr/lib/systemd/user/ytm-bar.service"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
  install -Dm644 fonts/OFL.txt "$pkgdir/usr/share/licenses/$pkgname/OFL.txt"
}
