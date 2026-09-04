# テスト方針・妥当性の記録

このリポジトリの既存機能（会員認証・商品一覧・カート・注文確定）は `tests/` 配下の結合テストで検証している。
テストの技術的な位置づけ（TestClientの仕組み等）は [README.md](README.md) を参照。

このドキュメントの目的は、**既存テストがどこまで保証していて、どこからが未検証か**を明確にすることである。
クーポン機能を追加する際、この境界線の外側（未検証の部分）を壊しても既存テストは気づけない。

## 試験観点マッピング

| エンドポイント   | 正常系                                                                | 異常系                                                                               | 境界値                                        |
| :--------------- | :-------------------------------------------------------------------- | :----------------------------------------------------------------------------------- | :-------------------------------------------- |
| POST /auth/login | `test_login_success`                                                  | `test_login_wrong_password`, `test_login_unknown_email`                              | -                                             |
| GET /products    | `test_list_products_returns_registered_product`                       | -                                                                                    | -                                             |
| POST /cart/items | `test_add_item_success`, `test_add_existing_item_increments_quantity` | `test_add_item_unknown_product`（`detail`文言も検証）, `test_add_item_without_login` | `test_add_item_negative_quantity_is_rejected` |
| GET /cart        | `test_get_empty_cart`                                                 | `test_get_cart_without_login`                                                        | -                                             |
| POST /orders     | `test_checkout_success`, `test_cart_is_cleared_after_checkout`        | `test_checkout_without_login`, `test_checkout_with_empty_cart`（`detail`文言も検証） | -                                             |

## 意図的にスコープ外としている項目

- **同時実行時の挙動**：テストはSQLiteのin-memory DBを使っており、リクエストは直列に処理される。実際の同時アクセス（発行数上限の競合等）は再現できない
- **負荷・性能**：範囲外

※ 以前は`seed.py`をスコープ外としていたが、現在は`tests/test_seed.py`で初回投入と再実行時スキップ（冪等性）を検証している。
※ 以前は他ユーザーのカート／注文分離もスコープ外としていたが、現在は`tests/test_cart.py`の`TestCartUserIsolation`と`tests/test_orders.py`の`TestOrderUserIsolation`で、他ユーザーのカート内容が見えないこと・チェックアウト時に他ユーザーのカート項目を巻き込まないことを検証している。

## カバレッジの数字だけでは分からないこと：ミューテーションテストの結果

`pytest --cov`によるカバレッジは87%だが、これは「実行されたか」を示すだけで「正しく検証されたか」は示さない。実際にミューテーションテスト（`mutmut`：コードにわざとバグを混入し、テストが検知できるかを測るツール）を実行し、テストが本当にバグを検知できるかを計測した。

### 実行方法

```bash
$env:PYTHONUTF8 = "1"   # Windowsのコンソール(cp932)だと完了時の絵文字出力でエラーになるため
mutmut run
mutmut results             # 変異ごとの結果一覧
mutmut show <変異ID>       # 個別の変異内容（diff）を確認
```

`mutmut`は`requirements.txt`に含まれている（`mutmut==2.5.1`）。3.xはネイティブWindows非対応（WSL必須）のため2.x系を使う。設定は `setup.cfg` の `[mutmut]` セクションを参照。

`requirements.txt`は**全パッケージをバージョン固定**している。この教材は「既存テスト55件PASS」を回帰試験の基準線として設計しており、依存ライブラリが更新されると基準線が再現しなくなるためである。固定値は2026-09-04時点の実測値。更新する場合は`pytest`が全件PASSすることを確認してから差し替える。

### 結果（2026-08-24実測、mutmut 2.5.1、テスト追加前）

| 指標                                 | 値                  |
| :----------------------------------- | :------------------ |
| 生成された変異数                     | 235                 |
| 検知（変異を入れたらテストが落ちた） | 96                  |
| 生存（変異を入れてもテストが通った） | 139                 |
| ミューテーションスコア               | **40.9%**（96/235） |

カバレッジ87%に対してミューテーションスコアは約41%と大きく乖離しており、「実行されているが検証されていないコード」が相当量あることを示している。

### 結果（2026-08-24実測、mutmut 2.5.1、テスト追加後）

| 指標                                 | 値                   |
| :----------------------------------- | :------------------- |
| 検知（変異を入れたらテストが落ちた） | 100                  |
| 生存（変異を入れてもテストが通った） | 135                  |
| ミューテーションスコア               | **42.6%**（100/235） |

下記「本物のギャップ」4件を追加テストで解決した分だけ検知数が96→100に増え、狙い通りの結果が確認できた。

### 結果（2026-08-25実測、mutmut 2.5.1、追加改善後）

| 指標                                 | 値                   |
| :----------------------------------- | :------------------- |
| 生成された変異数                     | 237                  |
| 検知（変異を入れたらテストが落ちた） | 143                  |
| 生存（変異を入れてもテストが通った） | 94                   |
| ミューテーションスコア               | **60.3%**（143/237） |

`tests/test_models.py`（モデル定義・制約・関連）、`tests/test_database.py`（`DATABASE_URL`分岐と`get_db`クローズ保証）、`tests/test_seed.py`（初回投入と冪等性）を追加した結果、前回（42.6%）から**+17.7pt**改善した。

### 結果（2026-08-25実測、mutmut 2.5.1、schemas/auth/main 追加後）

| 指標                                 | 値                   |
| :----------------------------------- | :------------------- |
| 生成された変異数                     | 237                  |
| 検知（変異を入れたらテストが落ちた） | 153                  |
| 生存（変異を入れてもテストが通った） | 84                   |
| ミューテーションスコア               | **64.6%**（153/237） |

`tests/test_schemas.py`、`tests/test_auth_core.py`、`tests/test_main.py`を追加した結果、直前（60.3%）から**+4.3pt**改善した（累計では42.6%比で**+22.0pt**）。

### 結果（2026-08-25実測、mutmut 2.5.1、seed データ内容検証テスト追加後）

| 指標                                 | 値                   |
| :----------------------------------- | :------------------- |
| 生成された変異数                     | 237                  |
| 検知（変異を入れたらテストが落ちた） | 173                  |
| 生存（変異を入れてもテストが通った） | 64                   |
| ミューテーションスコア               | **73.0%**（173/237） |

`tests/test_seed.py`に投入データの具体的な内容（商品の名前・価格・カテゴリー・セール状態、ユーザーのメール・ランク）を検証するテストを追加した結果、前回（64.6%）から**+8.4pt**改善した。seed.py の26件の生存変異のうち、大半がリテラル値の変異であり、投入データの内容検証により対処可能であることが判明した。

> **注意（mutmutの既知の制限）**：mutmutは終了コードが`1`（テスト失敗）かどうかだけで生存判定をしており（`returncode != 1`）、インポート時エラー等で終了コード`2`になるケースを誤って「生存」扱いする。実際に`app/routers/{cart,orders,products}.py`の生存変異を`mutmut apply <id>`で1件ずつ手動検証したところ、`APIRouter(prefix=...)`を壊す変異や`router = None`にする変異はテストの有無に関わらずFastAPI自身の起動時バリデーション（`AssertionError: A path prefix must start with '/'`等）やインポートエラーで即座にクラッシュしており、本来「検知」に分類されるべきだった。つまり**生存139件のうち一定数はmutmutの誤判定によるもので、実際のテスト網羅性はこの数字が示すより高い**。個別の生存変異に対応する際は、必ず`mutmut apply <id>`→`pytest`で実際にクラッシュするか手動確認すること。

### 手動検証で見つかった本物のギャップ（対応済み）

`app/routers/{cart,orders,products}.py`の生存変異13件（cart:4, orders:4, products:5）を全件手動検証した結果、本物のギャップは以下の4件だった（残りはプレフィックス破壊等の誤判定、または`tags`変更のような振る舞いに影響しない同値変異）。

**例1：`GET /products`のルーティングが壊れても気づかない**

```diff
-@router.get("", response_model=list[ProductOut])
+@router.get("XXXX", response_model=list[ProductOut])
 def list_products(db: Session = Depends(get_db)):
```

`GET /products`を実際に叩くテストが存在しなかったため、パスが変わっても404にすら気づけなかった。→ `test_list_products_returns_registered_product`を追加して解決。

**例2：エラーメッセージの文言を変えても気づかない**

```diff
 raise HTTPException(
     status_code=status.HTTP_404_NOT_FOUND, detail="商品が見つかりません"
+    status_code=status.HTTP_404_NOT_FOUND, detail="XX商品が見つかりませんXX"
 )
```

`cart.py`（商品未発見時）と`orders.py`（カート空時）で、`status_code`のみ確認し`detail`文言は未検証だった。→ 該当テストに`detail`のアサーションを追加して解決。

`app/routers/auth.py`の`test_login_wrong_password`にも同種のギャップがあったが、`tests/test_auth.py`に`detail`文言のアサーションを追加して対応済み。

### `database.py` が 100% 生存して見える根本要因

`tests/conftest.py`では、`app.database`の`engine`/`SessionLocal`を使わず、テスト専用のin-memory engineを作成し、`get_db`を`dependency_overrides`で差し替えている。結果として、`app/database.py`のモジュールレベル初期化（`DATABASE_URL`分岐、`engine`生成）と`get_db`本体は、現行テストスイートの実行パスにほぼ乗らない。

このため`database.py`の生存変異は「単なるassert不足」より「テスト設計上、間接テストで到達しない」影響が大きい。`database.py`を評価する場合は、アプリ結合テストではなく、環境変数のモンキーパッチや`importlib.reload`を使った直接ユニットテストで検証する必要がある。

### 生存変異の追加サンプリング結果（2026-08-25）

`tests/mutant_sample_results_batch2.json`に、追加20件の生存変異サンプリング結果を記録した。

| 指標                                                | 値  |
| :-------------------------------------------------- | :-- |
| サンプリング件数                                    | 20  |
| real_survivor（テストが通る本物の生存）             | 12  |
| false_survivor_crash（起動/インポート時クラッシュ） | 8   |

主な傾向:

- `app/routers/*.py`の生存は、今回サンプルでは全件が`false_survivor_crash`だった
- `app/models.py`のサンプル3件は全件`false_survivor_crash`だった
- `app/seed.py`・`app/auth.py`・`app/schemas.py`・`app/main.py`には`real_survivor`が残っており、追加テスト余地がある

### 結果（2026-08-25実測、mutmut 2.5.1、cross-user分離・auth.py環境変数分岐・schemas.py・models.py振る舞いテスト追加後）

| 指標                                 | 値                   |
| :----------------------------------- | :------------------- |
| 生成された変異数                     | 237                  |
| 検知（変異を入れたらテストが落ちた） | 186                  |
| 生存（変異を入れてもテストが通った） | 51                   |
| ミューテーションスコア               | **78.5%**（186/237） |

`tests/conftest.py`（`other_user`/`other_auth_headers`フィクスチャ追加）、`tests/test_cart.py`・`tests/test_orders.py`へのクロスユーザー分離テスト追加、`tests/test_auth_env.py`新規作成（`SECRET_KEY`/`ALGORITHM`/`EXPIRE_MINUTES`の環境変数フォールバック分岐を直接テスト）、`tests/test_schemas.py`への`LoginRequest`/`CartItemOut`/`OrderItemOut`/`OrderOut`テスト追加、`tests/test_models.py`への実DB挙動テスト（unique制約・relationship永続化）追加、`tests/test_database.py`のreload副作用修正（moduleスコープのautouseフィクスチャで復元）を行った結果、前回（73.0%）から**+5.5pt**改善した（累計では初回41.8%比で**+36.7pt**）。

内訳の変化: schemas.pyは6件生存が0件（全滅）、auth.pyは15件から9件、models.pyは17件から16件へ改善。database.py・main.py・seed.py・routersは今回のテストでは変化なし（database.pyはreloadの衛生修正のみで新規カバレッジ追加はしていないため）。

### 改善候補（優先順）

現在の生存変異51件の分布：

- auth.py（9件）: トークン生成/検証周辺の残存分
- models.py（16件）: モデル定義の同値変異の可能性
- routers/\*.py（12件）: うち8件は APIRouter prefix 破壊・`router = None`等の誤判定、4件は`tags=[...]`文言変更の本物の生存（優先度低）
- database.py（6件）: 環境変数名タイポ等、reload衛生修正のみでは解決しない残存分
- seed.py（6件）: 前回サンプリングでreal_survivorと判定された残存分
- main.py（2件）: health check 周辺
- schemas.py（0件）: 追加テストにより全滅

次の取り組み候補：

1. auth.py の残り9件を mutmut apply で個別確認し、本物のギャップ vs 同値変異を判定
2. models.py の残り16件のうち、テーブル定義・制約に関わる実質的な変異の有無をサンプリングではなく個別確認
3. database.py の環境変数名タイポ系変異（`os.getenv("DATABASE_URL", ...)`のキー名破壊等）を個別確認し、必要なら直接ユニットテストを追加
4. seed.py の残り6件を mutmut apply で個別確認し、real_survivorかどうかを再判定
5. routers/\*.py の`tags`変異4件は、アプリの実際の挙動に影響しないため対応は見送り（優先度低）

### routersの生存変異12件、全数検証結果（2026-08-25）

`mutmut apply <id>` と `pytest` を使い、`app/routers`配下4ファイル（`auth.py`, `cart.py`, `orders.py`, `products.py`）の生存変異12件（各ファイル3件）を全件手動検証した。サンプリングではなく全件確認済み。結果は以下の通り。

| 変異パターン                        | 該当ファイル数          | 判定                                               |
| :---------------------------------- | :---------------------- | :------------------------------------------------- |
| `APIRouter(prefix=...)`のprefix破壊 | 4ファイル各1件（計4件） | クラッシュ（mutmutの誤判定、実際は検知済み）       |
| `router = None`                     | 4ファイル各1件（計4件） | クラッシュ（mutmutの誤判定、実際は検知済み）       |
| `tags=[...]`の文言変更              | 4ファイル各1件（計4件） | 本物の生存（tagsを検証するテストが存在しないため） |

結論として、12件中8件は誤判定、4件（各ファイルのtags変異）が本物のテストギャップである。tagsはOpenAPIドキュメントの分類表示にのみ影響し、アプリの実際の挙動には影響しないため、優先度は低いと判断する。

## 参考：カバレッジの確認方法

```bash
pytest --cov=app --cov-report=term-missing
pytest --cov=app --cov-report=html   # htmlcov/index.html をブラウザで開く
```
