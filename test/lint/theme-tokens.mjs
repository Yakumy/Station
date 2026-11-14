import { readdir, readFile, lstat } from 'node:fs/promises';
import { resolve, relative, extname } from 'node:path';

// With no explicit root, scan runtime sources, not docs/tests/developer media.
// An explicit root retains the whole-tree mode used by scanner security fixtures.
const explicitRoot = process.argv[2];
const root = resolve(explicitRoot || '.');
const repositoryMode = !explicitRoot;
const textExtensions = new Set(['.qml', '.js', '.mjs', '.json', '.svg', '.css', '.html', '.lua']);
const runtimeDirectories = new Set(['lib', 'assets']);
// Approved branding artwork (docs/BRANDING.md), not theme-driven UI palettes.
// This is an exact-file exception, never an exemption for new files in assets/.
const brandingArtwork = new Set([
  'assets/station-main-logo.svg', 'assets/station-main-logo-mask.svg', 'assets/station-wordmark.svg'
]);

const HEX = /#(?:[\da-f]{8}|[\da-f]{6}|[\da-f]{4}|[\da-f]{3})(?![\da-f])/i;
const ELEVATION = /\b(?:DropShadow|FastBlur|GaussianBlur|MaskedBlur|RecursiveBlur|DirectionalBlur|RadialBlur|ZoomBlur|Glow)\s*\{/;
const SHADOW = /\b\w*shadow\w*\b/i;
const GRADIENT = /(?:^|[^\w])gradient\s*:|\bGradient\s*\{|(?:^|[^\w])stops\s*:/;
const APPROVED_DIM = /Qt\.darker\([^,()]+,\s*1\.4\s*\)/;
const APPROVED_ALPHA = /Util\.alpha\(Commons\.Color\.bar\.background,\s*0\.01\s*\)/;
const APPROVED_PILL_RADIUS = /Math\.min\(width,\s*height\)\s*\/\s*2/;
const MULTI_EFFECT_KEY = /^(?:id|source|width|height|x|y|visible|enabled|opacity|scale|anchors(?:\.\w+)?)$/;
const COLORISATION_KEY = /^(?:colorization(?:Enabled|Color)?|saturation)$/;

const stripComments = line => line.replace(/\/\/.*$/, '');
let violations = 0;
let files = 0;

function report(path, line, message) {
  console.error(`${relative(process.cwd(), path)}:${line}: ${message}`);
  violations++;
}

function checkLine(path, line, code) {
  if (HEX.test(code)) report(path, line, 'hex colour literal');
  const radius = code.match(/\bradius\s*:/);
  if (radius && !code.slice(code.indexOf(radius[0]) + radius[0].length).trimStart().startsWith('Style.cornerRadius')
      && !APPROVED_PILL_RADIUS.test(code)
      && !(path.endsWith("/WindowsLayout.qml") && code.trim() === "radius: canvas.values.rounding")
      && !(/\/(Display|Bar|Windows|Wallpaper|Workspaces|Color)Layout\.qml$/.test(path) && code.trim() === "radius: 0")) {
    report(path, line, 'radius not bound to Style.cornerRadius');
  }
  if (code.includes('Qt.rgba(')) report(path, line, 'Qt.rgba() literal colour mixing');
  if (code.includes('Qt.lighter(')) report(path, line, 'Qt.lighter() derives a Station-owned colour');
  if ((code.includes('Util.alpha(') && !APPROVED_ALPHA.test(code)) || code.includes('Qt.tint('))
    report(path, line, 'derived-colour helper outside the approved bar-blur fill or dim idiom');
  if (code.includes('Qt.darker(') && !APPROVED_DIM.test(code)) {
    report(path, line, 'Qt.darker must be the approved dim idiom Qt.darker(<token>, 1.4)');
  }
  if (GRADIENT.test(code)) report(path, line, 'gradient property');
  if (ELEVATION.test(code)) report(path, line, 'elevation effect (DropShadow/Glow/Blur family)');
  if (SHADOW.test(code)) report(path, line, 'shadow property');
}

function checkMultiEffect(path, source) {
  const opener = /\bMultiEffect\s*\{/g;
  let match;
  while ((match = opener.exec(source))) {
    const declarationLine = source.slice(0, match.index).split('\n').length;
    let depth = 1;
    let cursor = match.index + match[0].length;
    while (cursor < source.length && depth > 0) {
      if (source[cursor] === '{') depth++;
      else if (source[cursor] === '}') depth--;
      cursor++;
    }
    const body = source.slice(match.index + match[0].length, cursor - 1);
    let relativeDepth = 0;
    for (const raw of body.split('\n')) {
      const line = stripComments(raw);
      if (relativeDepth === 0) {
        const key = line.match(/^\s*([A-Za-z_$][\w$.]*)\s*:/);
        if (key && !MULTI_EFFECT_KEY.test(key[1]) && !COLORISATION_KEY.test(key[1])) {
          report(path, declarationLine, `MultiEffect property '${key[1]}' outside the icon color adjustment exception`);
        }
      }
      relativeDepth += (line.match(/\{/g) || []).length - (line.match(/\}/g) || []).length;
    }
  }
}

async function scan(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name);
    if (entry.isSymbolicLink()) throw new Error(`Refusing symlink: ${path}`);
    if (repositoryMode && directory === root && entry.isDirectory() && !runtimeDirectories.has(entry.name)) continue;
    if (repositoryMode && brandingArtwork.has(relative(root, path))) continue;
    if (entry.isDirectory()) await scan(path);
    else if (textExtensions.has(extname(path))) {
      files++;
      const source = await readFile(path, 'utf8');
      source.split('\n').forEach((line, i) => checkLine(path, i + 1, stripComments(line)));
      checkMultiEffect(path, source.split('\n').map(stripComments).join('\n'));
    }
  }
}

try {
  if (repositoryMode) {
    const manifestPath = resolve(root, 'manifest.json');
    if ((await lstat(manifestPath)).isSymbolicLink()) throw new Error(`Refusing symlink: ${manifestPath}`);
    const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
    if (!manifest.entryPoints || typeof manifest.entryPoints !== 'object' || Array.isArray(manifest.entryPoints))
      throw new Error('manifest.entryPoints must be an object');
    // Include declared runtime subtrees even if they eventually move outside lib/.
    for (const entry of Object.values(manifest.entryPoints)) {
      if (typeof entry !== 'string' || /[\\\x00-\x1f]/.test(entry)
          || entry.split('/').some(part => ['', '.', '..'].includes(part)))
        throw new Error(`Unsafe entry point: ${JSON.stringify(entry)}`);
      if (entry.includes('/')) runtimeDirectories.add(entry.split('/')[0]);
    }
  }
  await scan(root);
  console.log(`Theme tokens: scanned ${files} source files; ${violations} violations.`);
  process.exitCode = violations ? 1 : 0;
} catch (error) {
  // Missing sources must never be reported as a passing runtime check.
  console.error(error.message);
  process.exitCode = 1;
}
