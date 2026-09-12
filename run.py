"""Execute a .sql file against the supplied SQLite database and print results.

Usage: python run.py sql/01_table_inventory.sql
"""
import sqlite3
import sys
from pathlib import Path

DB = Path(__file__).parent / "data" / "comm_log.db"


def split_statements(text):
    """Split on semicolons, dropping comment-only and blank fragments."""
    out = []
    for raw in text.split(";"):
        body = "\n".join(
            line for line in raw.splitlines()
            if line.strip() and not line.strip().startswith("--")
        )
        if body.strip():
            out.append(raw.strip())
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