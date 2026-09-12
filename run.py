"""Execute a .sql file against the supplied SQLite database and print results.

Usage: python run.py sql/01_table_inventory.sql
"""
import sqlite3
import sys
from pathlib import Path

DB = Path(__file__).parent / "data" / "comm_log.db"


def split_statements(text):
    """Split on semicolons, ignoring those inside -- comments."""
    out, buf, code = [], [], []
    for line in text.splitlines():
        buf.append(line)
        stripped = line.split("--")[0]
        code.append(stripped)
        if ";" in stripped:
            stmt = "\n".join(buf).strip()
            if "\n".join(code).strip().rstrip(";").strip():
                out.append(stmt)
            buf, code = [], []
    if "\n".join(code).strip():
        out.append("\n".join(buf).strip())
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