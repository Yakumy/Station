const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const zlib = require('node:zlib');
const {spawnSync} = require('node:child_process');

const helper = path.resolve('lib/SanitizeWallpaper.pl');

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const name = Buffer.from(type, 'ascii');
  const size = Buffer.alloc(4); size.writeUInt32BE(data.length);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([name, data])));
  return Buffer.concat([size, name, data, crc]);
}

function pngWithCompressedText(count = 24) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(1, 0); header.writeUInt32BE(1, 4);
  header[8] = 8; header[9] = 6;
  const metadata = [];
  for (let i = 0; i < count; i++) {
    const compressed = zlib.deflateSync(Buffer.alloc(512 * 1024, 65));
    metadata.push(chunk('zTXt', Buffer.concat([Buffer.from(`Comment${i}\0\0`), compressed])));
  }
  const pixels = zlib.deflateSync(Buffer.from([0, 255, 0, 0, 255]));
  return Buffer.concat([
    Buffer.from('89504e470d0a1a0a', 'hex'), chunk('IHDR', header), ...metadata,
    chunk('IDAT', pixels), chunk('IEND', Buffer.alloc(0)),
  ]);
}

function chunks(png) {
  const result = [];
  for (let offset = 8; offset < png.length;) {
    const length = png.readUInt32BE(offset);
    result.push({type: png.toString('ascii', offset + 4, offset + 8),
      data: png.subarray(offset + 8, offset + 8 + length)});
    offset += 12 + length;
  }
  return result;
}

test('the staging helper strips compressed PNG metadata without decoding it', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'station-wallpaper-sanitize-'));
  try {
    const source = path.join(root, 'renamed.jpg');
    const input = pngWithCompressedText();
    fs.writeFileSync(source, input);
    assert.ok(input.length < 32 * 1024, 'the compressed fixture should remain small');

    const destination = path.join(root, 'wallpapers', 'private');
    const result = spawnSync('perl', [helper, source, destination], {encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
    const outputPath = result.stdout.trim();
    assert.equal(outputPath, path.join(destination, 'image.png'));
    const output = fs.readFileSync(outputPath);
    assert.deepEqual(chunks(output).map(value => value.type), ['IHDR', 'IDAT', 'IEND']);
    assert.deepEqual(chunks(output).find(value => value.type === 'IDAT').data,
      chunks(input).find(value => value.type === 'IDAT').data);
    assert.equal(fs.statSync(path.dirname(destination)).mode & 0o777, 0o700);
    assert.equal(fs.statSync(destination).mode & 0o777, 0o700);
    assert.equal(fs.statSync(outputPath).mode & 0o777, 0o600);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('the staging helper rejects malformed and unsupported files without leaving output', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'station-wallpaper-reject-'));
  try {
    const source = path.join(root, 'not-an-image.png');
    fs.writeFileSync(source, 'not an image');
    const destination = path.join(root, 'private');
    const result = spawnSync('perl', [helper, source, destination], {encoding: 'utf8'});
    assert.notEqual(result.status, 0);
    assert.equal(fs.existsSync(destination), false);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('the staging helper refuses a symlink source', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'station-wallpaper-symlink-'));
  try {
    const target = path.join(root, 'target.png');
    const source = path.join(root, 'chosen.png');
    fs.writeFileSync(target, pngWithCompressedText(1));
    fs.symlinkSync(target, source);
    const destination = path.join(root, 'private');
    const result = spawnSync('perl', [helper, source, destination], {encoding: 'utf8'});
    assert.notEqual(result.status, 0);
    assert.equal(fs.existsSync(destination), false);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});
