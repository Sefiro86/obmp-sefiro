# Lightweight check of Lua scripts without an interpreter: invalid escapes in quoted strings, strings not
# closed on their line, and balance between opened (function/if/for/while/do/repeat) and closed (end/until) blocks.
# It does not replace a real parser: it finds the errors that automatic replacements have already caused.
# Usage: python -I lua_string_check.py <file.lua>
import re
import sys

VALID = set('abfnrtvz"\'\\\n0123456789xu')

def strip_comments_and_strings(src):
    out, i, n, line = [], 0, len(src), 1
    problems = []
    while i < n:
        c = src[i]
        if src.startswith("--[[", i) or src.startswith("--[=[", i):
            j = src.find("]]", i)
            j = n if j < 0 else j + 2
            line += src.count("\n", i, j); out.append(" " * 0 + "\n" * src.count("\n", i, j)); i = j; continue
        if src.startswith("--", i):
            j = src.find("\n", i); j = n if j < 0 else j
            i = j; continue
        if src.startswith("[[", i) or src.startswith("[=[", i):
            j = src.find("]]", i); j = n if j < 0 else j + 2
            out.append(" S " + "\n" * src.count("\n", i, j)); line += src.count("\n", i, j); i = j; continue
        if c in "\"'":
            q, j = c, i + 1
            while j < n and src[j] != q:
                if src[j] == "\n":
                    problems.append((line, "unclosed string"))
                    break
                if src[j] == "\\":
                    if j + 1 < n and src[j + 1] not in VALID:
                        problems.append((line, f"invalid escape \\{src[j + 1]}"))
                    j += 2; continue
                j += 1
            out.append(" S "); i = j + 1; continue
        if c == "\n":
            line += 1
        out.append(c); i += 1
    return "".join(out), problems

def main(path):
    src = open(path, encoding="utf-8").read()
    code, problems = strip_comments_and_strings(src)
    depth = 0
    for ln, text in enumerate(code.split("\n"), 1):
        for tok in re.findall(r"\b(function|if|for|while|repeat|do|then|end|until|elseif)\b", text):
            if tok in ("function", "if", "repeat"): depth += 1
            elif tok in ("for", "while"): depth += 0   # closed by their "do"
            elif tok == "do": depth += 1
            elif tok in ("end", "until"): depth -= 1
        if depth < 0:
            problems.append((ln, "more ends than blocks")); depth = 0
    for ln, msg in problems:
        print(f"{path}:{ln}: {msg}")
    print(f"open blocks at end of file: {depth}" + ("" if depth == 0 else "  <-- unbalanced"))
    return 1 if problems or depth else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
