"""Execute a .sql file against the supplied SQLite database and print results.

Usage: python run.py sql/01_table_inventory.sql
"""
import sqlite3
import sys
from pathlib import Path

DB = Path(__file__).parent / "data" / "comm_log.db"

def split_statements(text):
    """Split on semicolons that are outside string literals and comments."""
    out, buf = [], []
    in_str = False
    i = 0
    while i < len(text):
        ch = text[i]
        if in_str:
            if ch == "'":
                if i + 1 < len(text) and text[i + 1] == "'":
                    buf.append("''"); i += 2; continue
                in_str = False
            buf.append(ch); i += 1; continue
        if ch == "'":
            in_str = True; buf.append(ch); i += 1; continue
        if text[i:i+2] == "--":
            j = text.find("\n", i)
            j = len(text) if j == -1 else j
            buf.append(text[i:j]); i = j; continue
        if ch == ";":
            stmt = "".join(buf).strip()
            if any(l.strip() and not l.strip().startswith("--") for l in stmt.splitlines()):
                out.append(stmt + ";")
            buf = []; i += 1; continue
        buf.append(ch); i += 1
    tail = "".join(buf).strip()
    if any(l.strip() and not l.strip().startswith("--") for l in tail.splitlines()):
        out.append(tail)
    return out

def render(cur):
    cols = [d[0] for d in cur.description]
    rows = [tuple("" if v is None else str(v) for v in r) for r in cur.fetchall()]
    widths = [
        max(len(c), *(len(r[i]) for r in rows)) if rows else len(c)
        for i, c in enumerate(cols)
    ]
    print("  ".join(c.ljust(widths[i]) for i, c in enumerate(cols)))
    print("  ".join("-" * w for w in widths))
    for r in rows:
        print("  ".join(r[i].ljust(widths[i]) for i in range(len(cols))))
    print(f"({len(rows)} rows)\n")


def main():
    path = Path(sys.argv[1])
    conn = sqlite3.connect(DB)
    for stmt in split_statements(path.read_text(encoding="utf-8")):
        label = next(
            (l.strip() for l in stmt.splitlines() if l.strip().startswith("--")),
            "",
        )
        print("=" * 70)
        print(label or stmt.splitlines()[0][:70])
        print("=" * 70)
        render(conn.execute(stmt))
    conn.close()


if __name__ == "__main__":
    main()