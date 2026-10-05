import { readdir, readFile } from 'node:fs/promises';
import { resolve, relative, extname } from 'node:path';

// Reference palettes and v1 are not v2 runtime code. Scan the whole v2 plugin,
// including future assets, rather than maintaining individual file exclusions.
const explicitRoot = process.argv[2];
const root = resolve(explicitRoot || '.');
const repositoryMode = !explicitRoot;
const repositoryRuntimeFiles = new Set(['Panel.qml', 'Service.qml', 'manifest.json']);
const textExtensions = new Set(['.qml', '.js', '.mjs', '.json', '.svg', '.css', '.html', '.lua']);
let violations = 0;
let files = 0;
async function scan(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name);
    if (entry.isSymbolicLink()) throw new Error(`Refusing symlink: ${path}`);
    if (repositoryMode && directory === root && entry.isDirectory() && entry.name !== 'lib') continue;
    if (repositoryMode && directory === root && !entry.isDirectory() && !repositoryRuntimeFiles.has(entry.name)) continue;
    if (entry.isDirectory()) await scan(path);
    else if (textExtensions.has(extname(path))) {
      files++;
      const lines = (await readFile(path, 'utf8')).split('\n');
      lines.forEach((line, i) => {
        // Also reject short and alpha variants; all palette values use tokens.
        if (/#(?:[\da-f]{8}|[\da-f]{6}|[\da-f]{4}|[\da-f]{3})(?![\da-f])/i.test(line)) {
          console.error(`${relative(process.cwd(), path)}:${i + 1}: hex colour literal`);
          violations++;
        }
      });
    }
  }
}
try {
  await scan(root);
  console.log(`Theme tokens: scanned ${files} source files; ${violations} violations.`);
  process.exitCode = violations ? 1 : 0;
} catch (error) {
  // Missing sources must never be reported as a passing runtime check.
  console.error(error.message);
  process.exitCode = 1;
}
