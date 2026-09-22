This directory holds local and release binaries produced by Bun. Generated
files in this directory are ignored by Git.

Release binaries must be built by `.github/workflows/release.yml` with the
digest-pinned Bun image and must match the reviewed checksum under
`release/checksums/`. See the "Build and release provenance" and "Reviewer
verification" sections of `README.md` for the authoritative build procedure.
