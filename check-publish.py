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

検査対象は precheck.ps1・README.md・docs-template/*.md と、このファイル自身。
このファイルの FORBIDDEN・ALLOW_LINE の定義行は、検査する語をそのまま含むので外す。

結果は OK: / NG: の形で出す。NG が1つでもあれば終了コード 1 で終わる。
Python 3.11 以上の標準ライブラリだけで動く。ファイルは書き換えない。
"""

import argparse
import re
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
    "settings.local.json",  # Claude Code の設定ファイル名（-Diagnose で読む）。ホスト名ではない
    "伏せるため",
    "伏せる情報",
    "件数は事前確認書",
]


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
    """FORBIDDEN・ALLOW_LINE の定義行の行番号。自身を検査するときに外す。"""
    skip: set[int] = set()
    inside = False
    for i, line in enumerate(text.splitlines(), 1):
        if re.match(r"^(FORBIDDEN|ALLOW_LINE) = \[", line):
            inside = True
        if inside:
            skip.add(i)
            if line.strip() == "]":
                inside = False
    return skip


def check_publishable(names: list[str]) -> bool:
    """公開してはいけない情報が混ざっていないかを見る。"""
    hits = []
    for name in names:
        text = read(HERE / name)
        skip = definition_lines(text) if name == SELF else set()
        for i, line in enumerate(text.splitlines(), 1):
            if i in skip:
                continue
            if any(a in line for a in ALLOW_LINE):
                continue
            for pattern, label in FORBIDDEN:
                m = re.search(pattern, line)
                if m:
                    hits.append(f"{name}:{i}: {label} … {m.group(0)}")
    if hits:
        print("NG: 公開できない内容が含まれている:\n    " + "\n    ".join(hits), file=sys.stderr)
        return False
    print(f"OK: 公開してはいけない情報は見つからない（{len(names)}ファイル・{len(FORBIDDEN)}種類を検査）")
    return True


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
    a = p.parse_args()

    names = targets()
    ok = names is not None and check_publishable(names)
    if a.doc:
        ok = check_consistency(Path(a.doc)) and ok
    else:
        print("省略: 整合検査は省略した（事前確認書は教材リポジトリにある。--doc でパスを渡すと行う）")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
