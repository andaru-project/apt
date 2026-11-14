# Andaru APT repository

The signed Debian package repository for [Andaru](https://github.com/andaru-project/andaru), served at <https://apt.andaru.io/>.

Packages are signed by Andaru's archive key and trusted only for this repository (`Signed-By:`), never added to global APT trust. Installation instructions and the key's fingerprint are in Andaru's documentation.

The site is not kept in this repository: `.github/workflows/publish.yml` rebuilds it daily, and on demand, from Andaru's GitHub releases (`bin/select-tags`, `bin/build-site`), signs it with the archive's signing subkey (the `APT_SIGNING_KEY` secret of the `signing` environment, which only `main` may use, and which exists only here) and deploys it to GitHub Pages. The daily run keeps `Valid-Until` (14 days) from lapsing. To publish a release at once: `gh workflow run publish -R andaru-project/apt`.

- `trixie` serves the five newest Andaru releases; `trixie-test` also serves the release candidates newer than the newest release.
- Every package must match its release's `SHA256SUMS`, or nothing is published.
- `sh tests/test.sh` tests the scripts with a throwaway key (needs `dpkg`, `apt-utils`, `gpg`, `gpgv`).
