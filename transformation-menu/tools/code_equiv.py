# Compares two versions of a source file ignoring comments and string contents: used to verify that
# a translation of comments and messages did not touch the code. Languages: .lua, .cs, .py, .html (script+markup).
# Usage: python -I code_equiv.py <before> <after>      (exit 0 = identical code)
import re
import sys


def tokens_lua(s):
    out, i, n = [], 0, len(s)
    while i < n:
        if s.startswith("--", i):
            m = re.match(r"--\[(=*)\[", s[i:])
            if m:
                end = s.find("]" + m.group(1) + "]", i)
                i = n if end < 0 else end + len(m.group(1)) + 2
            else:
                j = s.find("\n", i); i = n if j < 0 else j
            continue
        m = re.match(r"\[(=*)\[", s[i:])
        if m:
            end = s.find("]" + m.group(1) + "]", i)
            out.append("STR"); i = n if end < 0 else end + len(m.group(1)) + 2; continue
        c = s[i]
        if c in "\"'":
            j = i + 1
            while j < n and s[j] != c:
                j += 2 if s[j] == "\\" else 1
            out.append("STR"); i = j + 1; continue
        if c.isspace():
            i += 1; continue
        m = re.match(r"[A-Za-z_][A-Za-z0-9_]*|0[xX][0-9A-Fa-f]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\.\.|\.\.|==|~=|<=|>=|//|::|.", s[i:])
        out.append(m.group(0)); i += len(m.group(0))
    return out


def tokens_c_like(s, py=False):
    out, i, n = [], 0, len(s)
    while i < n:
        if not py and s.startswith("//", i):
            j = s.find("\n", i); i = n if j < 0 else j; continue
        if not py and s.startswith("/*", i):
            j = s.find("*/", i); i = n if j < 0 else j + 2; continue
        if py and s[i] == "#":
            j = s.find("\n", i); i = n if j < 0 else j; continue
        m = re.match(r'(?i)(?:[rbfu]{0,3})("""|\'\'\'|"|\')' if py else r'(\$@|@\$|\$|@)?(""")?"', s[i:])
        if m:
            if py:
                q = m.group(1); j = i + len(m.group(0))
                end = s.find(q, j) if len(q) == 3 else None
                if len(q) == 3:
                    i = n if end < 0 else end + 3
                else:
                    while j < n and s[j] != q and s[j] != "\n":
                        j += 2 if s[j] == "\\" else 1
                    i = j + 1
            else:
                verbatim = m.group(1) and "@" in m.group(1)
                j = i + len(m.group(0))
                while j < n:
                    if s[j] == "\\" and not verbatim: j += 2; continue
                    if s[j] == '"':
                        if verbatim and j + 1 < n and s[j + 1] == '"': j += 2; continue
                        break
                    j += 1
                i = j + 1
            out.append("STR"); continue
        if not py and s[i] == "'":
            j = i + 1
            while j < n and s[j] != "'":
                j += 2 if s[j] == "\\" else 1
            out.append("CHR"); i = j + 1; continue
        if s[i].isspace():
            i += 1; continue
        m = re.match(r"[A-Za-z_][A-Za-z0-9_]*|0[xX][0-9A-Fa-f]+|\d+\.?\d*[A-Za-z]*|=>|==|!=|<=|>=|&&|\|\||\?\?|::|.", s[i:])
        out.append(m.group(0)); i += len(m.group(0))
    return out


def tokens_html(s):
    # visible text and free comments; only the <script> blocks are compared, with the JS (C-like) rule
    scripts = re.findall(r"<script>(.*?)</script>", s, re.S)
    styles = re.findall(r"<style>(.*?)</style>", s, re.S)
    out = []
    for sc in scripts:
        out += tokens_c_like(re.sub(r"`[^`]*`", '"T"', sc))
    for st in styles:
        out += re.findall(r"[^\s]+", re.sub(r"/\*.*?\*/", "", st, flags=re.S))
    return out


def tokens(path, text):
    if path.endswith(".lua"): return tokens_lua(text)
    if path.endswith(".py"): return tokens_c_like(text, py=True)
    if path.endswith(".html"): return tokens_html(text)
    return tokens_c_like(text)


def main(a, b):
    ta = tokens(a, open(a, encoding="utf-8").read())
    tb = tokens(b, open(b, encoding="utf-8").read())
    if ta == tb:
        print(f"IDENTICO ({len(ta)} tokens): {b}")
        return 0
    k = next((i for i, (x, y) in enumerate(zip(ta, tb)) if x != y), min(len(ta), len(tb)))
    print(f"DIVERSO at token {k}: before {ta[max(0, k - 6):k + 6]} / after {tb[max(0, k - 6):k + 6]} ({b})")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
