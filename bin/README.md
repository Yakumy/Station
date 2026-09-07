This directory holds the release binary produced by Bun.

For x86_64 Omarchy/Arch:
  bun build --compile --minify --bytecode --target=bun-linux-x64 ./index.js --outfile bin/station

For ARM64 releases:
  bun build --compile --minify --bytecode --target=bun-linux-arm64 ./index.js --outfile bin/station
