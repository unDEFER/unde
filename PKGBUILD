# Maintainer: Nikolay (unDEFER) Krivchenkov <undefer@gmail.com>
pkgname=unde
pkgver=0.2.0
pkgrel=1
epoch=
pkgdesc="Ultimate Native Desktop Environment"
arch=(x86_64)
url="http://unde.su"
license=('GPL3')
groups=()
depends=('ttf-liberation' 'ttf-symbola' 'sdl2' 'sdl2_image' 'sdl2_ttf' 'coreutils' 'rsync' 'util-linux' 'db')
makedepends=('dmd' 'dub' 'db')
checkdepends=()
optdepends=()
provides=()
conflicts=()
replaces=()
backup=()
options=()
install=
changelog=
source=("$pkgname-$pkgver.tar.xz")
noextract=()
md5sums=("INSERT-REAL-MD5SUM-HERE")
validpgpkeys=()

prepare() {
	cd "$pkgname-$pkgver"
}

build() {
	cd "$pkgname-$pkgver"
	dub build -c Manjaro
}

check() {
	cd "$pkgname-$pkgver"
}

package() {
	cd "$pkgname-$pkgver"
	make DESTDIR="$pkgdir/" install
}
