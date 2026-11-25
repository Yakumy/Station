#!/usr/bin/env python3
"""Find and print one section of Station's documentation, so nobody reads whole files.

    docs/find.py                          every document, with its size in tokens
    docs/find.py bar blur passes          the sections that answer those words
    docs/find.py lib/color/ColorMatch.js  the documents and sections about a file
    docs/find.py contracts/bars           the outline of one document
    docs/find.py contracts/bars#controls  print one section
    docs/find.py --index                  rewrite the generated index tables
    docs/find.py --check                  links, sizes, code map and indexes (test/run.py)

Each document starts with a `summary` comment, and a `code` comment when it covers
source files. See docs/README.md.
"""
from pathlib import Path
import difflib
import fnmatch
import math
import os
import re
import sys

DOCS = Path(__file__).resolve().parent
ROOT = DOCS.parent
# A document that one read cannot afford is the problem this layout solves.
MAX_DOC = 12_500      # bytes, about 3,100 tokens
MAX_SECTION = 5_000   # bytes, about 1,250 tokens
UNLIMITED = {"CHANGELOG"}   # history, read by section only
DATED = "Dated sections are investigations, oldest first. A later one can supersede an earlier one."
EXTRA = {"CHANGELOG": "What changed in each version, newest first. Print only the version you need.",
         "README": "The page users read: features, defaults, install, keybindings."}
INDEX = re.compile(r"<!-- index(?: ([\w/-]*))? -->\n.*?<!-- /index -->", re.S)
FILLER = set("a an the is are was be do does did to of in on at it its and or for with how why what when "
             "where which that this can my i not from by as".split())
LINK = re.compile(r"\]\(([^)\s]+)\)")


def tokens(text):
    return max(1, len(text.encode()) // 4)


def slug(heading):
    return re.sub(r"[^\w\- ]", "", heading.lower()).replace(" ", "-")


class Section:
    def __init__(self, title, level, anchor):
        self.title, self.level, self.anchor, self.lines = title, level, anchor, []

    @property
    def body(self):
        return "\n".join(self.lines).strip("\n")


class Document:
    def __init__(self, name, path):
        self.name, self.path, self.text = name, path, path.read_text()
        self.summary = self._meta("summary") or EXTRA.get(name, "")
        self.code = (self._meta("code") or "").split()
        self.sections, seen, fenced = [], {}, False
        for line in self.text.split("\n"):
            if line.startswith("```"):
                fenced = not fenced
            heading = None if fenced else re.match(r"(#{1,4}) (.+)", line)
            if heading:
                base = slug(heading[2])
                count = seen.get(base, 0)
                seen[base] = count + 1
                self.sections.append(Section(heading[2], len(heading[1]), f"{base}-{count}" if count else base))
            elif self.sections:
                self.sections[-1].lines.append(line)

    def _meta(self, key):
        # Only the lines before the title, so an example further down is not metadata.
        found = re.search(rf"^<!-- {key}: (.+?) -->$", self.text.split("\n# ")[0], re.M)
        return found[1] if found else None

    @property
    def title(self):
        return self.sections[0].title

    def covers(self, path):
        """How specifically this document claims a source file: 0 when it does not."""
        return max((len(glob.replace("*", "")) + 1 for glob in self.code
                    if fnmatch.fnmatch(path, glob.replace("**/", "*").replace("**", "*"))), default=0)


def load():
    found = {p.relative_to(DOCS).with_suffix("").as_posix(): p for p in sorted(DOCS.rglob("*.md"))}
    found["docs"] = found.pop("README")
    for name in EXTRA:
        found[name] = ROOT / f"{name}.md"
    return {name: Document(name, path) for name, path in found.items()}


def stem(word):
    word = re.sub(r"(?<=\w{3})(?:ing|ed|es|s|e)$", "", word.lower())
    return re.sub(r"([b-df-hj-np-tv-z])\1$", r"\1", word)   # unplugged and unplug


def words(text):
    # workspaceMode and bar-blur are also found by their parts.
    out = []
    for word in re.findall(r"[A-Za-z][A-Za-z0-9]*|[0-9]+", text):
        out.append(stem(word))
        parts = re.findall(r"[A-Z]?[a-z0-9]+|[A-Z]+(?![a-z])", word)
        if len(parts) > 1:
            out += [stem(part) for part in parts]
    return out


def search(docs, query, limit=8):
    useful = " ".join(word for word in query.split() if word.lower() not in FILLER)
    query = list(dict.fromkeys(words(useful or query)))
    entries = [(d, s, words(s.title), words(INDEX.sub("", s.body)), words(f"{d.name} {d.summary}"))
               for d in docs.values() for s in d.sections if s.body and s.body != DATED]
    rarity = {q: math.log(1 + len(entries) / (1 + sum(q in b or q in t for _, _, t, b, _ in entries)))
              for q in query}
    scored = []
    for d, s, title, body, about in entries:
        score = matched = 0
        for q in query:
            hits = body.count(q)
            part = 4 * (q in title) + 1.5 * (q in about) + 2 * hits / (hits + 1.5 + len(body) / 250)
            score += part * rarity[q]
            matched += q in title or hits > 0
        if matched:
            # Current rules first, then evidence, then history.
            weight = 0.5 if d.name in UNLIMITED else 1.2 if d.name.startswith("contracts") else 1
            scored.append((score * weight * (matched / len(query)) ** 2, d, s))
    scored.sort(key=lambda item: -item[0])
    return [(d, s) for _, d, s in scored[:limit]]


def row(d, s, indent=""):
    return f"{indent}{d.name}#{s.anchor}  {tokens(s.body)}t"


def show_file(docs, path):
    covering = sorted(((d.covers(path), d) for d in docs.values() if d.covers(path)), key=lambda x: -x[0])
    name = Path(path).stem
    # A backticked or bare mention of the file or type.
    mention = re.compile(rf"(?<![\w-]){re.escape(name)}(?![\w-])")
    for _, d in covering[:6]:
        print(f"{d.name}  {tokens(d.text)}t  {d.summary}")
    hits = [(d, s) for d in docs.values() for s in d.sections
            if d.name not in UNLIMITED and mention.search(s.body)]
    if hits:
        print(f"\nsections that name {name}:")
        for d, s in hits[:10]:
            print(row(d, s, "  "))
    if not covering and not hits:
        raise SystemExit(f"no document covers {path}")


def show(docs, target):
    name, _, anchor = target.removeprefix("docs/").partition("#")
    name = name.removesuffix(".md")
    d = docs.get(name)
    if d is None:
        raise SystemExit(f"no document {name}: {', '.join(difflib.get_close_matches(name, docs, 3, 0.3))}")
    if not anchor:
        print(f"{d.name}  {tokens(d.text)}t  {d.summary}")
        for s in d.sections:
            print(f"{'  ' * s.level}#{s.anchor}  {tokens(s.body)}t")
        return
    at = next((i for i, s in enumerate(d.sections) if s.anchor == anchor), None)
    if at is None:   # A unique part of the anchor is enough.
        near = [i for i, s in enumerate(d.sections) if anchor in s.anchor]
        if len(near) != 1:
            raise SystemExit(f"no section #{anchor} in {name}: "
                             + ", ".join("#" + s.anchor for s in d.sections))
        at = near[0]
    s = d.sections[at]
    print(f"{'#' * s.level} {s.title}\n\n{s.body}")
    below = []
    for child in d.sections[at + 1:]:
        if child.level <= s.level:
            break
        below.append(child)
    if below and at:
        print("\n[below: " + ", ".join(f"#{c.anchor} {tokens(c.body)}t" for c in below) + "]")


def index_table(docs, doc, folder):
    here = doc.path.parent
    rows = ["| Read | For | Tokens |", "| --- | --- | --- |"]
    for d in docs.values():
        if folder and not d.name.startswith(folder + "/"):
            continue
        if not folder and ("/" in d.name or d.name in EXTRA or d is doc):
            continue
        link = os.path.relpath(d.path, here)
        # Rounded to the next 100, so a small edit does not change the table.
        rows.append(f"| [{d.title}]({link}) | {d.summary} | {math.ceil(tokens(d.text) / 100) * 100} |")
    return "\n".join(rows)


def indexed(docs, doc):
    return INDEX.sub(lambda m: f"<!-- index{' ' + m[1] if m[1] else ''} -->\n"
                     f"{index_table(docs, doc, m[1])}\n<!-- /index -->", doc.text)


def sources():
    return sorted(p.relative_to(ROOT).as_posix() for p in
                  [*ROOT.glob("*.qml"), *(q for q in ROOT.glob("lib/**/*") if q.suffix in (".qml", ".js", ".pl"))])


def check(docs):
    problems = []
    files = [p.relative_to(ROOT).as_posix() for p in ROOT.rglob("*") if p.is_file() and ".git" not in p.parts]
    by_path = {d.path.resolve(): d for d in docs.values()}
    agents = Document("AGENTS", ROOT / "AGENTS.md")
    for d in [*docs.values(), agents]:
        label = d.path.relative_to(ROOT)
        if d is not agents and not d.summary:
            problems.append(f"{label}: no summary comment")
        if d.name not in UNLIMITED | {"README"}:
            size = len(d.text.encode())
            if size > MAX_DOC:
                problems.append(f"{label}: {size} bytes, over {MAX_DOC}. Split it by topic.")
            problems += [f"{label}#{s.anchor}: {len(s.body.encode())} bytes, over {MAX_SECTION}. Add a heading."
                         for s in d.sections if len(s.body.encode()) > MAX_SECTION]
        for glob in d.code:
            if not any(fnmatch.fnmatch(f, glob.replace("**/", "*").replace("**", "*")) for f in files):
                problems.append(f"{label}: code pattern {glob} matches no file")
        prose = re.sub(r"^```.*?^```", "", d.text, flags=re.M | re.S)
        for target in LINK.findall(prose):
            if re.match(r"\w+:", target):
                continue
            file, _, anchor = target.partition("#")
            path = (d.path.parent / file).resolve() if file else d.path.resolve()
            if not path.exists():
                problems.append(f"{label}: broken link {target}")
            elif anchor:
                other = agents if path == agents.path else by_path.get(path)
                if other and anchor not in {s.anchor for s in other.sections}:
                    problems.append(f"{label}: no such section {target}")
        if INDEX.search(d.text) and indexed(docs, d) != d.text:
            problems.append(f"{label}: index is stale. Run python3 docs/find.py --index")
    problems += [f"{path}: no document covers it" for path in sources()
                 if not any(d.covers(path) for d in docs.values())]
    for problem in problems:
        print(problem)
    print(f"{len(docs)} documents, {sum(tokens(d.text) for d in docs.values())} tokens, {len(problems)} problems")
    raise SystemExit(1 if problems else 0)


def main():
    docs, args = load(), sys.argv[1:]
    if args in (["-h"], ["--help"]):
        print(__doc__)
    elif not args:
        for d in docs.values():
            print(f"{d.name}  {tokens(d.text)}t  {d.summary}")
    elif args == ["--check"]:
        check(docs)
    elif args == ["--index"]:
        # One index can change the size that another one lists.
        while stale := [d for d in docs.values() if indexed(docs, d) != d.text]:
            for d in stale:
                d.path.write_text(indexed(docs, d))
            docs = load()
    elif len(args) == 1 and args[0] in sources():
        show_file(docs, args[0])
    elif len(args) == 1 and ("#" in args[0] or args[0].removeprefix("docs/").removesuffix(".md") in docs):
        show(docs, args[0])
    elif len(args) == 1 and re.search(r"\.(qml|js|pl|py|cjs|mjs)$", args[0]):
        matches = [s for s in sources() if s.endswith("/" + args[0]) or s == args[0]]
        show_file(docs, matches[0] if matches else args[0])
    else:
        found = search(docs, " ".join(args))
        if not found:
            raise SystemExit("nothing found")
        for d, s in found:
            print(row(d, s))


main()
