// Splits a QML file into named units by its indentation, so two versions of one
// file can be compared member by member: 'BarPanel/PopupWindow#tooltipWindow/visible'.
// It relies on the two-space indentation both bars use, and ignores comments.

function strip(source) {
  return source.split('\n').filter(line => !/^\s*\/\//.test(line)).map(line => line.trimEnd());
}

function nameOf(line, body) {
  let m;
  if ((m = line.match(/^component (\w+)/))) return m[1];
  if ((m = line.match(/^(?:function|signal) (\w+)/))) return `${m[1]}()`;
  if ((m = line.match(/^(?:required |readonly |default )*property [\w<>.]+ (\w+)/))) return m[1];
  if ((m = line.match(/^([a-zA-Z_][\w.]*)\s*:/))) return m[1];
  if ((m = line.match(/^Behavior on (\w+)/))) return `Behavior:${m[1]}`;
  if ((m = line.match(/^([A-Z][\w.]*)\s*\{/))) {
    const id = body.map(l => l.match(/\bid: (\w+)/)).find(Boolean);
    return id ? `${m[1]}#${id[1]}` : m[1];
  }
  return line.slice(0, 60);
}

// Braces opened less closed, strings left out.
function depth(text) {
  const bare = text.join('\n').replace(/"(?:[^"\\]|\\.)*"|\/(?![/*])(?:[^/\n\\]|\\.)+\//g, '');
  return [...bare].reduce((n, c) => n + ('{[('.includes(c) ? 1 : '}])'.includes(c) ? -1 : 0), 0);
}

// Only these open a block whose members are worth naming one by one.
const nested = line => /^component \w+\s*:/.test(line) || /^[A-Z][\w.]*\s*\{$/.test(line);

function units(lines, indent, prefix, out) {
  const pad = ' '.repeat(indent);
  const starts = [];
  lines.forEach((line, i) => {
    if (line.startsWith(pad) && line[indent] !== ' ' && line.length > indent && !/^[}\])]/.test(line.slice(indent))) starts.push(i);
  });
  const seen = new Map();
  starts.forEach((start, k) => {
    const body = lines.slice(start, starts[k + 1] ?? lines.length);
    const line = body[0].slice(indent);
    let name = prefix + nameOf(line, body.slice(1, 3));
    const count = (seen.get(name) || 0) + 1;
    seen.set(name, count);
    if (count > 1) name += `[${count}]`;
    if (nested(line)) {
      out.set(name, line.replace(/\s+/g, ' '));
      units(body.slice(1), indent + 2, name + '/', out);
    } else {
      const text = body.map(l => l.trim()).filter(l => l);
      // A leaf that ends its block drags the block's own braces along.
      while (text.length > 1 && /^[}\])]+$/.test(text[text.length - 1]) && depth(text) < 0) text.pop();
      out.set(name, text.join('\n'));
    }
  });
  return out;
}

// Members of the file's root object, and everything inside its components.
function qmlUnits(source) {
  const lines = strip(source);
  const root = lines.findIndex(line => /^[A-Z][\w.]*\s*\{$/.test(line));
  return units(lines.slice(root + 1), 2, '', new Map());
}

module.exports = { qmlUnits };
