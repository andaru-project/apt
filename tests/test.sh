#!/bin/sh
# Tests bin/select-tags and bin/build-site with fake packages and a throwaway key. Needs dpkg-deb, apt-ftparchive,
# gpg and gpgv (Debian: dpkg, apt-utils, gpg, gpgv).
# shellcheck disable=SC2016,SC2034 # check() evaluates its quoted condition, with these variables
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
	# shellcheck disable=SC2016 # the checks are evaluated here, with the test's variables
	if eval "$2"; then
		echo "ok - $1"
	else
		echo "not ok - $1"
		failures=$((failures + 1))
	fi
}

# select-tags: every keyring release, the five newest releases, and the candidates newer than the newest release.
selected=$(printf '%s\n' v0.4.0 v0.4.0-rc1 v0.3.0 v0.5.0 v0.10.0 keyring-2026.11.14 v0.9.0 v0.2.0 v0.11.0-rc1 v0.9.0-rc1 |
	sh "$here/bin/select-tags" | sort | tr '\n' ' ')
check "select-tags keeps the keyring, five releases and newer candidates" \
	'[ "$selected" = "keyring-2026.11.14 v0.10.0 v0.11.0-rc1 v0.3.0 v0.4.0 v0.5.0 v0.9.0 " ]'
selected=$(printf '%s\n' v0.4.0 v0.5.0-rc1 v0.5.0-rc2 v0.5.0-rc3 v0.5.0-rc4 v0.5.0-rc5 v0.5.0-rc6 | sh "$here/bin/select-tags" |
	sort | tr '\n' ' ')
check "candidates never evict the newest release" '[ "$selected" = "v0.4.0 v0.5.0-rc1 v0.5.0-rc2 v0.5.0-rc3 v0.5.0-rc4 v0.5.0-rc5 v0.5.0-rc6 " ]'
selected=$(printf '%s\n' v0.4 vfoo v1.2.3-rc keyring-x v0.4.0 | sh "$here/bin/select-tags" | tr '\n' ' ')
check "select-tags ignores tags that are not releases" '[ "$selected" = "v0.4.0 " ]'

selected=$(printf '%s\n' v01.2.3 v1.02.3 v1.2.03 v1x2y3 v1.2.3-rc01 v1x2.3-rc1 keyring-2026x11x14 v1.2.3 | sh "$here/bin/select-tags" |
	tr '\n' ' ')
check "select-tags wants no leading zeros and literal dots" '[ "$selected" = "v1.2.3 " ]'

# check-expiry: fails when the signing subkey expires within the given days.
# shellcheck disable=SC2030,SC2031 # the subshell keeps the expiry key's GNUPGHOME apart
(
	export GNUPGHOME="$work/gnupg-expiry"
	mkdir -m 0700 "$GNUPGHOME"
	gpg --batch --quiet --no-tty --passphrase '' --quick-gen-key 'Exp <exp@example.invalid>' ed25519 cert never
	p=$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')
	gpg --batch --quiet --no-tty --passphrase '' --quick-add-key "$p" ed25519 sign 30d
	k=$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { n++ } $1 == "fpr" && n == 2 { print $10 }')
	echo "$k" >"$work/expiring-key"
)
expiring=$(cat "$work/expiring-key")
check "check-expiry fails for a subkey expiring within the window" \
	'! GNUPGHOME="$work/gnupg-expiry" sh "$here/bin/check-expiry" "$expiring" 90 2>/dev/null'
check "check-expiry passes for a subkey expiring after the window" \
	'GNUPGHOME="$work/gnupg-expiry" sh "$here/bin/check-expiry" "$expiring" 10'

# A throwaway signing key, as the workflow imports the real subkey.
# shellcheck disable=SC2031 # the subshell above used its own GNUPGHOME
export GNUPGHOME="$work/gnupg"
mkdir -m 0700 "$GNUPGHOME"
printf "%s\n" quiet >"$GNUPGHOME/gpg.conf"
# As the archive key: a certify-only primary and a signing subkey, and only the subkey's secret is here.
gpg --batch --quiet --no-tty --passphrase '' --quick-gen-key 'Test <test@example.invalid>' ed25519 cert never
primary=$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')
gpg --batch --quiet --no-tty --passphrase '' --quick-add-key "$primary" ed25519 sign never
SIGNING_KEY=$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { n++ } $1 == "fpr" && n == 2 { print $10 }')
export SIGNING_KEY
gpg --batch --export "$primary" >"$work/keyring.gpg"
gpg --batch --export-secret-subkeys "$SIGNING_KEY!" >"$work/subkey.gpg"
gpg --batch --yes --delete-secret-keys "$primary"
gpg --batch --quiet --import "$work/subkey.gpg"

deb() { # deb TAG PACKAGE VERSION ARCH
	d=$work/pkg/$2-$3-$4
	mkdir -p "$d/DEBIAN" "$work/releases/$1"
	chmod 0755 "$d" "$d/DEBIAN"
	printf 'Package: %s\nVersion: %s\nArchitecture: %s\nMaintainer: t <t@t>\nDescription: t\n' "$2" "$3" "$4" >"$d/DEBIAN/control"
	dpkg-deb -b "$d" "$work/releases/$1/$2_$3_$4.deb" >/dev/null
}
sums() { (cd "$work/releases/$1" && sha256sum ./*.deb | sed 's| \./| |' >SHA256SUMS); }

deb keyring-2026.11.14 andaru-archive-keyring 2026.11.14 all
sums keyring-2026.11.14
deb v0.4.0 andaru 0.4.0-1 amd64
deb v0.4.0 andaru 0.4.0-1 arm64
sums v0.4.0
deb v0.5.0-rc1 andaru '0.5.0~rc1-1' amd64
sums v0.5.0-rc1
deb v0.6.0-rc1 andaru '0.6.0~rc1-1' amd64
sums v0.6.0-rc1
touch "$work/releases/v0.5.0-rc1/prerelease"

sh "$here/bin/build-site" "$work/releases" "$work/site"
site=$work/site

check "InRelease verifies with the signing key" \
	'gpgv --keyring "$work/keyring.gpg" "$site/dists/trixie/InRelease" 2>/dev/null'
check "Release.gpg verifies with the signing key" \
	'gpgv --keyring "$work/keyring.gpg" "$site/dists/trixie/Release.gpg" "$site/dists/trixie/Release" 2>/dev/null'
date=$(sed -n 's/^Date: //p' "$site/dists/trixie/Release")
until=$(sed -n 's/^Valid-Until: //p' "$site/dists/trixie/Release")
check "Valid-Until is 14 days after Date" \
	'[ $(($(date -d "$until" +%s) - $(date -d "$date" +%s))) -eq 1209600 ]'
check "a release reaches trixie" \
	'grep -qx "Version: 0.4.0-1" "$site/dists/trixie/main/binary-arm64/Packages"'
check "a prerelease stays out of trixie" \
	'! grep -q "~rc1" "$site/dists/trixie/main/binary-amd64/Packages"'
check "a candidate without GitHub's prerelease flag stays out of trixie" \
	'! grep -qF "0.6.0~rc1" "$site/dists/trixie/main/binary-amd64/Packages"'
check "a prerelease reaches trixie-test" \
	'grep -qx "Version: 0.5.0~rc1-1" "$site/dists/trixie-test/main/binary-amd64/Packages"'
check "the keyring is in both architectures' indexes" \
	'grep -qx "Package: andaru-archive-keyring" "$site/dists/trixie/main/binary-arm64/Packages"'
check "the bootstrap package and its checksum are at the root" \
	'(cd "$site" && sha256sum -c --quiet SHA256SUMS) && [ -f "$site/andaru-archive-keyring_2026.11.14_all.deb" ]'
check "the public key is at the root" '[ -f "$site/andaru-archive-key.asc" ]'
check "Packages.gz matches Packages" \
	'gzip -dc "$site/dists/trixie/main/binary-amd64/Packages.gz" | cmp -s - "$site/dists/trixie/main/binary-amd64/Packages"'

for suite in trixie trixie-test; do
	r=$site/dists/$suite/Release
	check "$suite Release names itself, its origin and both architectures" \
		'grep -qx "Suite: $suite" "$r" && grep -qx "Codename: $suite" "$r" && grep -qx "Origin: Andaru" "$r" &&
		grep -qx "Architectures: amd64 arm64" "$r"'
done
check "Release asks clients for by-hash" 'grep -qx "Acquire-By-Hash: yes" "$site/dists/trixie/Release"'
packages=$site/dists/trixie/main/binary-amd64/Packages
sum=$(sha256sum "$packages" | cut -d' ' -f1)
check "Packages is also served by hash" '[ -f "$(dirname "$packages")/by-hash/SHA256/$sum" ] && cmp -s "$packages" "$(dirname "$packages")/by-hash/SHA256/$sum"'

# The previous run's indexes stay under by-hash, for clients holding the CDN's cached previous InRelease.
prev=$work/previous/dists/trixie/main/binary-amd64
mkdir -p "$prev"
echo old >"$prev/Packages"
gzip -n -c "$prev/Packages" >"$prev/Packages.gz"
sh "$here/bin/build-site" "$work/releases" "$work/site-prev" "$work/previous" 2>/dev/null || true
oldsum=$(sha256sum "$prev/Packages" | cut -d' ' -f1)
oldgzsum=$(sha256sum "$prev/Packages.gz" | cut -d' ' -f1)
h=$work/site-prev/dists/trixie/main/binary-amd64/by-hash/SHA256
check "the previous Packages and Packages.gz are kept by hash" \
	'cmp -s "$prev/Packages" "$h/$oldsum" && cmp -s "$prev/Packages.gz" "$h/$oldgzsum"'

# download-releases: a release without a .deb or SHA256SUMS is skipped with a warning, a complete one is fetched.
mkdir "$work/fakebin"
cat >"$work/fakebin/gh" <<'F'
#!/bin/sh
# Fake gh: release view TAG prints the assets (v1: complete, v2: no SHA256SUMS, v3: no assets); release download TAG -D DIR.
tag=$3
case $2 in
view) case $tag in v1) printf 'a.deb\nSHA256SUMS\n' ;; v2) echo a.deb ;; esac ;;
download) while [ "$1" != -D ]; do shift; done; mkdir -p "$2"; : >"$2/a.deb" ;;
esac
F
chmod +x "$work/fakebin/gh"
printf '%s\n' 'v1 true' 'v2 false' 'v3 false' >"$work/rel.txt"
out=$(printf '%s\n' v1 v2 v3 | PATH="$work/fakebin:$PATH" sh "$here/bin/download-releases" "$work/rel.txt" "$work/dl")
check "download-releases skips an incomplete release with a warning" \
	'[ -f "$work/dl/v1/a.deb" ] && [ -f "$work/dl/v1/prerelease" ] && [ ! -e "$work/dl/v2" ] && [ ! -e "$work/dl/v3" ] &&
	printf "%s\n" "$out" | grep -q "^::warning::.*v2" && printf "%s\n" "$out" | grep -q "^::warning::.*v3"'

# Without any prerelease, trixie still has every release.
mkdir "$work/releases-only"
cp -r "$work/releases/v0.4.0" "$work/releases/keyring-2026.11.14" "$work/releases-only/"
sh "$here/bin/build-site" "$work/releases-only" "$work/site-only"
check "without a prerelease, trixie has the releases" \
	'grep -qx "Version: 0.4.0-1" "$work/site-only/dists/trixie/main/binary-amd64/Packages"'

# A package that does not match its release's checksums is refused, and nothing is built.
echo corrupt >>"$work/releases/v0.4.0/andaru_0.4.0-1_amd64.deb"
check "a package failing its checksum is refused" \
	'! sh "$here/bin/build-site" "$work/releases" "$work/refused" 2>/dev/null && [ ! -e "$work/refused" ]'
# A package missing from SHA256SUMS is refused too.
sums v0.4.0
deb v0.4.0 andaru-extra 0.4.0-1 amd64
check "a package missing from its checksums is refused" \
	'! sh "$here/bin/build-site" "$work/releases" "$work/refused" 2>/dev/null && [ ! -e "$work/refused" ]'

# A name that matches a listed one only as a regular expression (. for -) is not listed.
rm "$work/releases/v0.4.0/andaru-extra_0.4.0-1_amd64.deb"
deb v0.4.0 andaru-extra 0.4.0-1 amd64
sums v0.4.0
deb v0.4.0 andaru.extra 0.4.0-1 amd64
check "a package listed only by a regular-expression match is refused" \
	'! sh "$here/bin/build-site" "$work/releases" "$work/refused" 2>/dev/null && [ ! -e "$work/refused" ]'

[ "$failures" -eq 0 ] || {
	echo "$failures failed"
	exit 1
}
