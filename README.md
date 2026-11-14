# Andaru APT repository

The signed Debian package repository for [Andaru](https://github.com/andaru-project/andaru), served at <https://apt.andaru.io/>.

Packages are signed by Andaru's archive key and trusted only for this repository (`Signed-By:`), never added to global APT trust. Installation instructions and the key's fingerprint are in Andaru's documentation.

The site is not kept in this repository: `.github/workflows/publish.yml` rebuilds it daily, and on demand, from Andaru's GitHub releases (`bin/select-tags`, `bin/download-releases`, `bin/build-site`), signs it with the archive's signing subkey (the `APT_SIGNING_KEY` secret of the `signing` environment, which only `main` may use, and which exists only here) and deploys it to GitHub Pages. The daily run keeps `Valid-Until` (14 days) from lapsing. To publish a release at once: `gh workflow run publish -R andaru-project/apt`.

- `trixie` serves the five newest Andaru releases; `trixie-test` also serves the release candidates newer than the newest release.
- Every package must match its release's `SHA256SUMS`, or nothing is published.
- A release without a `.deb` or without `SHA256SUMS` (for example one published before its assets were uploaded) is skipped with a workflow warning (`bin/download-releases`), so it cannot halt publishing. The keyring release is the exception: without it the build stops with an error, since the bootstrap package is missing.
- Indexes are also served under `by-hash/` (`Acquire-By-Hash: yes`), so a client never mixes a new `InRelease` with a cached old `Packages`. Each run also keeps the live site's previous `Packages.gz` there, under every hash directory (`SHA256` and `SHA512`), so a client holding the CDN's cached previous `InRelease` still finds it.
- When a scheduled or manual run fails, the workflow opens an issue titled "Publishing failed" with the run URL, or comments on the open one. `bin/check-expiry` also checks that the signing subkey and its primary key stay valid for 90 days; if not, publishing continues and the workflow opens (or comments on) a "Signing key expires soon" issue.
- `sh tests/test.sh` tests the scripts with a throwaway key (needs `dpkg`, `apt-utils`, `gpg`, `gpgv`).
