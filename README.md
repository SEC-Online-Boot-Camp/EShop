# rehearsal ブランチ（講師専用）

AI活用入門講座 SW編の**事前リハーサル**で使うものを置いてある。**受講者はこのブランチを使わない。**

`main`・`No3`とは履歴を共有しない独立したブランチで、**アプリのコードは入っていない**。受講者が`git clone`したときに、このブランチの内容が作業ツリーへ展開されないようにするためである。

> **このブランチは公開リポジトリにあり、受講者からも参照できる。** 普通の`git clone`はすべてのブランチをリモート追跡ブランチとして取得するため、`git show origin/rehearsal:precheck.ps1`で中身を読める。**受講者に伏せたい情報（演習の答え・仕込んだ欠陥の件数など）はここに書かない。** 期待するテスト件数（54件・55件）は配布する手順書（03-01〜03-03）に既に書かれているので差し支えない。

## 中身

| ファイル                              | 用途                                                                       |
| :------------------------------------ | :------------------------------------------------------------------------- |
| `precheck.ps1`                        | 事前確認書 第I部（実機確認）を1ステップずつ進める対話型ランナー            |
| `docs-template/要件整理メモ.md`       | リハーサル用のダミー成果物。本来はNo.2で受講者が作るもの                   |
| `docs-template/クーポンAPI設計書.md`  | 同上                                                                       |

`docs-template`の2ファイルは、`precheck.ps1`の4-4-01でリハーサル機の`EShop/docs/`へコピーされる。No.3の手順書（03-01〜03-03）がNo.2の成果物を参照する前提で書かれているため、リハーサルではこれで代用する。**解答例は講師専用資料なので、このPublicリポジトリには置かない。**

## 使い方

リハーサル機で次を実行する。受講者が使う`main`・`No3`は取得されない。

```powershell
$base = "C:\rehearsal-$(Get-Date -Format 'yyyyMMdd')"
New-Item -ItemType Directory -Force $base | Out-Null
Set-Location $base
git clone -b rehearsal --single-branch https://github.com/SEC-Online-Boot-Camp/EShop.git EShop-rehearsal
Set-Location EShop-rehearsal
.\precheck.ps1 -DryRun            # 下見
.\precheck.ps1 -OnSite            # 実環境リハーサル（止まる箇所を絞る）
.\precheck.ps1                    # 全項目を1つずつ確認する
```

`.ps1`の実行が実行ポリシーで禁止されている場合の起動方法は`precheck.ps1`の冒頭に書いてある。

## 置き場所

**作業フォルダ（EShopのclone先）と記録の出力先は、既定で`C:\rehearsal-<日付>`になる。** 上のとおりこのスクリプトも同じフォルダに置けば、**リハーサルが終わったらフォルダごと1回で片付く**。

```text
C:\rehearsal-<日付>\
├── EShop-rehearsal\      ← このリポジトリのクローン
├── EShop\                ← 4-3-05 でcloneする作業ツリー
├── precheck-result-<日時>.md
├── precheck-steps-<日時>.md
└── rehearsal-check.txt
```

- **`EShop`の中には置かない。** 入れ子のリポジトリになり、7-1の`git status`の判定がぶれる
- **デスクトップに置かない。** 貸与機ではKnown Folder Moveでデスクトップが客先テナントのOneDrive配下になっていることがある。`.venv`と`.git`が同期対象になると**6章の所要時間の実測が当てにならなくなり**、記録の方も機材から消してクラウド側に残る
- `C:\`直下に作れない機材では`%USERPROFILE%\rehearsal-<日付>`へ自動で退避する。`-WorkDir`・`-OutDir`で明示することもできる（OneDrive配下を指した場合は起動時に警告が出る）

## 保守

`precheck.ps1`のステップ番号・期待値は、**教材リポジトリにある`事前確認書.md`（第I部）と対になっている**。どちらかを直したら、もう一方も合わせること。

- ステップ番号は同書の節番号と揃えてある（`3-2-1`・`4-3-05`・`7-2-b`など）
- 期待値の出どころ: 同書 4-3（`main` 54件）・4-4（`No3` 55件）・5章
