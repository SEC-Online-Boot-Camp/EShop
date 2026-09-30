"""rehearsal ブランチを push する前に、公開してよい内容かを検査するスクリプト。

このブランチ（EShop の rehearsal）が正本で、公開リポジトリにある。受講者も
`git show origin/rehearsal:precheck.ps1` で中身を読めるため、push する前に、受講者に
伏せる情報と客先のネットワーク情報が混ざっていないかを検査する。

使い方:

    python check-publish.py
        公開の可否だけを検査する。事前確認書との整合検査は省略する

    python check-publish.py --doc <事前確認書.md のパス>
        あわせて、precheck.ps1 のステップIDが事前確認書の章立てと対応しているかを見る。
        事前確認書は教材リポジトリにあるので、パスで渡す

    python check-publish.py --file <パス> [--file <パス> ...]
        任意のファイルも、配布ブランチのファイルと同じ基準で検査する。main・coupon へ
        tools/check-setup.ps1 を入れる PR をマージする前に、作業ツリーのファイルを確かめるため

検査対象は precheck.ps1・README.md・docs-template/*.md と、このファイル自身。
このファイルの FORBIDDEN・ALLOW_LINE・FORBIDDEN_DIST の定義行は、検査する語をそのまま
含むので外す。

あわせて、配布ブランチ（origin/main・origin/coupon）の tools/check-setup.ps1 を、この
スクリプトを置いたリポジトリで git show して検査する（fetch はしない）。講座当日の
診断はこのファイルで行う。ref かファイルが無ければ「省略:」と出して先へ進む。
配布ブランチのファイルと --file のファイルには、FORBIDDEN に加えて FORBIDDEN_DIST
（演習の答えになる語）も NG にする。受講者の作業ツリーに入り、Claude Code も読むため。
main と coupon の両方にあれば blob が同じかも見る（違うと、受講者が git switch coupon
したときに中身が変わる）。

結果は OK: / NG: の形で出す。NG が1つでもあれば終了コード 1 で終わる。
Python 3.11 以上の標準ライブラリだけで動く。ファイルは書き換えない。
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SELF = Path(__file__).resolve().name

# 必ずあるはずのもの。docs-template/*.md はこれに加えて全部を見る
REQUIRED = ["precheck.ps1", "README.md"]

# 公開してはいけないもの。このブランチは公開リポジトリなので、push 前に弾く。
FORBIDDEN = [
    (r"欠陥[^\n]{0,10}?\d+\s*件", "仕込んだ欠陥の件数（演習の答えになる）"),
    (r"(?<!\d)(?!127\.0\.0\.1)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}", "IPアドレス"),
    (r"[\w.-]+\.pac\b", "PACのURL"),
    (r"[\w-]+\.local\b", "社内のホスト名"),
    (r"\.sec\.co\.jp", "社内のドメイン"),
    (r"C:\\Users\\[A-Za-z0-9]+\\", "利用者名を含むローカルパス"),
]

# 検査から外す行（説明のために語を含むもの）
ALLOW_LINE = [
    "proxy.example.local",  # プレースホルダ
    "settings.local.json",  # Claude Code の設定ファイル名（tools/check-setup.ps1 で読む）。ホスト名ではない
    "伏せるため",
    "伏せる情報",
    "件数は事前確認書",
]

# 配布ブランチ（main・coupon）のファイルと --file のファイルにだけ加える禁止語。
# 受講者の作業ツリーに入り、Claude Code も読むため、03-02 の hook の作り方（演習の答え）を弾く。
FORBIDDEN_DIST = [
    (r"ls-files", "hook で追跡の有無を見る方法（演習の答えになる）"),
    (r"sys\.exit\(2\)", "hook で止める方法（演習の答えになる）"),
    (r"Edit\|Write", "hook の matcher（演習の答えになる）"),
]

# 配布ブランチの検査対象
DIST_REFS = ["origin/main", "origin/coupon"]
DIST_FILE = "tools/check-setup.ps1"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def targets() -> list[str] | None:
    """検査するファイルの一覧。必須のものが欠けていれば None。"""
    missing = [n for n in REQUIRED if not (HERE / n).is_file()]
    if missing:
        print("NG: 検査対象が見つからない: " + " / ".join(missing), file=sys.stderr)
        return None
    docs = sorted(p.relative_to(HERE).as_posix() for p in (HERE / "docs-template").glob("*.md"))
    return REQUIRED + docs + [SELF]


def definition_lines(text: str) -> set[int]:
    """FORBIDDEN・ALLOW_LINE・FORBIDDEN_DIST の定義行の行番号。自身を検査するときに外す。"""
    skip: set[int] = set()
    inside = False
    for i, line in enumerate(text.splitlines(), 1):
        if re.match(r"^(FORBIDDEN|ALLOW_LINE|FORBIDDEN_DIST) = \[", line):
            inside = True
        if inside:
            skip.add(i)
            if line.strip() == "]":
                inside = False
    return skip


def find_hits(name: str, text: str, patterns: list[tuple[str, str]], skip: set[int] | None = None) -> list[str]:
    """patterns に当たる行を「名前:行番号: ラベル … 当たった文字列」の形で返す。"""
    hits = []
    for i, line in enumerate(text.splitlines(), 1):
        if skip and i in skip:
            continue
        if any(a in line for a in ALLOW_LINE):
            continue
        for pattern, label in patterns:
            m = re.search(pattern, line)
            if m:
                hits.append(f"{name}:{i}: {label} … {m.group(0)}")
    return hits


def report(hits: list[str], ok_message: str) -> bool:
    if hits:
        print("NG: 公開できない内容が含まれている:\n    " + "\n    ".join(hits), file=sys.stderr)
        return False
    print(ok_message)
    return True


def check_publishable(names: list[str]) -> bool:
    """公開してはいけない情報が混ざっていないかを見る。"""
    hits = []
    for name in names:
        text = read(HERE / name)
        skip = definition_lines(text) if name == SELF else set()
        hits += find_hits(name, text, FORBIDDEN, skip)
    return report(hits, f"OK: 公開してはいけない情報は見つからない（{len(names)}ファイル・{len(FORBIDDEN)}種類を検査）")


def git(*args: str) -> subprocess.CompletedProcess:
    """このスクリプトを置いたリポジトリで git を実行する。出力はバイト列のまま返す。"""
    return subprocess.run(["git", "-C", str(HERE), *args], capture_output=True)


def check_dist_text(name: str, text: str) -> list[str]:
    """配布ブランチに入るファイルの基準（FORBIDDEN と FORBIDDEN_DIST）で検査する。"""
    return find_hits(name, text, FORBIDDEN + FORBIDDEN_DIST)


def check_dist() -> bool:
    """配布ブランチの tools/check-setup.ps1 を検査する。ref かファイルが無ければ省略する。"""
    ok = True
    blobs: dict[str, str] = {}
    kinds = len(FORBIDDEN) + len(FORBIDDEN_DIST)
    for ref in DIST_REFS:
        spec = f"{ref}:{DIST_FILE}"
        r = git("rev-parse", "--verify", "--quiet", spec)
        if r.returncode != 0:
            print(f"省略: {spec} が無い（ref かファイルが無い）")
            continue
        blobs[ref] = r.stdout.decode("ascii").strip()
        r = git("show", spec)
        if r.returncode != 0:
            print(f"NG: {spec} を読めない: {r.stderr.decode('utf-8', 'replace').strip()}", file=sys.stderr)
            ok = False
            continue
        text = r.stdout.decode("utf-8-sig", "replace")
        ok = report(check_dist_text(spec, text), f"OK: {spec} に公開してはいけない情報は見つからない（{kinds}種類を検査）") and ok
    if len(blobs) == len(DIST_REFS):
        if len(set(blobs.values())) == 1:
            print(f"OK: {DIST_FILE} は {'・'.join(DIST_REFS)} で同じ内容（blob {next(iter(blobs.values()))[:7]}）")
        else:
            detail = " / ".join(f"{ref}: {b[:7]}" for ref, b in blobs.items())
            print(f"NG: {DIST_FILE} が配布ブランチで食い違っている（{detail}）。受講者が git switch coupon したときに中身が変わる", file=sys.stderr)
            ok = False
    return ok


def check_files(paths: list[str]) -> bool:
    """--file で渡したファイルを、配布ブランチのファイルと同じ基準で検査する。"""
    ok = True
    kinds = len(FORBIDDEN) + len(FORBIDDEN_DIST)
    for p in paths:
        path = Path(p)
        if not path.is_file():
            print(f"NG: --file のファイルが見つからない: {p}", file=sys.stderr)
            ok = False
            continue
        ok = report(check_dist_text(p, read(path)), f"OK: {p} に公開してはいけない情報は見つからない（{kinds}種類を検査）") and ok
    return ok


def check_consistency(doc_path: Path) -> bool:
    """事前確認書とステップIDが食い違っていないかを見る。"""
    if not doc_path.is_file():
        print(f"NG: 事前確認書が見つからない: {doc_path}", file=sys.stderr)
        return False
    doc = read(doc_path)
    ps1 = read(HERE / "precheck.ps1")
    ids = re.findall(r"New-Step -Id '([^']+)'", ps1)
    if not ids:
        print("NG: precheck.ps1 からステップIDを読み取れない", file=sys.stderr)
        return False

    doc_sections = set(re.findall(r"^#### (\d+-\d+)\.", doc, re.MULTILINE))
    doc_chapters = set(re.findall(r"^### (\d+)\.", doc, re.MULTILINE))
    # 小見出しを持つ章だけ、節の対応も見る（5章のように表の行で並ぶ章は章の一致だけ）
    sectioned = {s.split("-")[0] for s in doc_sections}

    unknown = []
    for sid in ids:
        ch = sid.split("-")[0]
        if ch not in doc_chapters:
            unknown.append(f"{sid}（{ch}章が事前確認書に無い）")
            continue
        parts = sid.split("-")
        if len(parts) < 2 or ch not in sectioned:
            continue
        sec = f"{parts[0]}-{parts[1]}"
        if sec not in doc_sections and not sid.endswith("-0"):
            unknown.append(f"{sid}（節 {sec} が事前確認書に無い）")
    if unknown:
        print("NG: 事前確認書と対応しないステップがある:\n    " + "\n    ".join(unknown), file=sys.stderr)
        return False
    print(f"OK: ステップ{len(ids)}件が事前確認書の章立てと対応している")
    return True


def main() -> int:
    p = argparse.ArgumentParser(description="rehearsal ブランチを push する前に、公開してよい内容かを検査する")
    p.add_argument("--doc", help="事前確認書.md のパス（教材リポジトリ）。渡したときだけ整合検査を行う")
    p.add_argument("--file", action="append", default=[], metavar="PATH",
                   help="配布ブランチのファイルと同じ基準で検査するファイル（複数回指定可）")
    a = p.parse_args()

    names = targets()
    ok = names is not None and check_publishable(names)
    ok = check_dist() and ok
    if a.file:
        ok = check_files(a.file) and ok
    if a.doc:
        ok = check_consistency(Path(a.doc)) and ok
    else:
        print("省略: 整合検査は省略した（事前確認書は教材リポジトリにある。--doc でパスを渡すと行う）")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
