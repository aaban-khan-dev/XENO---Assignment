"""Run the target_base reconciliation against the supplied SQLite database.

  python run.py                  bridge table and the final number
  python run.py --trail          the full investigation, sql/
  python run.py --extra          additional analysis, extra_sql/
  python run.py <path.sql>       a single file

The supplied database is never written to. Files in extra_sql/ create
indexes to compare query plans, so they run against a temporary copy
that is deleted afterwards.
"""
import shutil
import sqlite3
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).parent
DB = ROOT / "data" / "comm_log.db"
SQL = ROOT / "sql"
EXTRA_SQL = ROOT / "extra_sql"


def files_in(folder):
    """All .sql files in a folder, in filename order."""
    return sorted(folder.glob("*.sql"))


def answer_files():
    """The bridge and the final metric - what the reconciliation asks for."""
    wanted = ("bridge", "target_base")
    found = [p for w in wanted for p in files_in(SQL) if w in p.name]
    return found or files_in(SQL)


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
    if cur.description is None:
        return
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


def run_file(conn, path):
    print("\n" + "=" * 78)
    print(f"  {path.name}")
    print("=" * 78 + "\n")
    for stmt in split_statements(path.read_text(encoding="utf-8")):
        label = next(
            (l.strip().lstrip("- ") for l in stmt.splitlines()
             if l.strip().startswith("--") and "===" not in l),
            "",
        )
        if label:
            print(f"-- {label}")
        render(conn.execute(stmt))


def run_readonly(paths):
    """Read-only connection: SQLite refuses any write, so the supplied
    database provably cannot be modified by these queries."""
    conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    for p in paths:
        run_file(conn, p)
    conn.close()


def run_on_copy(paths):
    """These queries create and drop indexes, so work on a throwaway copy."""
    tmpdir = Path(tempfile.mkdtemp())
    tmp = tmpdir / "comm_log_copy.db"
    shutil.copy(DB, tmp)
    print(f"(temporary copy: {tmp} - the supplied database is untouched)")
    try:
        conn = sqlite3.connect(tmp)
        for p in paths:
            run_file(conn, p)
        conn.close()
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def main():
    args = sys.argv[1:]
    if not args:
        run_readonly(answer_files())
    elif args[0] == "--trail":
        run_readonly(files_in(SQL))
    elif args[0] == "--extra":
        run_on_copy(files_in(EXTRA_SQL))
    else:
        path = Path(args[0])
        if not path.is_absolute():
            path = ROOT / path
        if EXTRA_SQL.name in path.parts:
            run_on_copy([path])
        else:
            run_readonly([path])


if __name__ == "__main__":
    main()