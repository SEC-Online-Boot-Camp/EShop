<#
    講座当日の診断（EShop が講座を始められる状態かを確かめる）

    受講者のPCで、受講者が自分の EShop を診断する。講師は画面共有で結果を見る。
    読み取りだけで、ファイルは変えない。clone・pip・seed・DBの削除・ブランチの切り替え・
    サーバーの起動は行わない。NG・注意の項目には手順書のどの手順をやり直すかを表示するので、
    直す操作は手順書どおりに受講者が行う。

    書き込むのは EShop の外に置く記録ファイルと、pytest を走らせる間だけ使う一時フォルダ
    （%TEMP% に作り、終わったら消す）だけ。pytest にはキャッシュとバイトコードを書かせない。
    .env の値は画面共有に映るため表示しない（キー名と形だけを見る）。

    ブランチごとに違う期待値（期待するブランチ名・段階・要るファイルとテーブル・テストの件数）は
    同じフォルダの check-setup.json に書いてあり、このスクリプトはどのブランチでも同じ内容にしてある。
    check-setup.json が無い・読めないときは、ブランチごとの判定を「未確認」にして、ほかの項目を続ける。

    起動方法（EShop のフォルダを開いた VS Code のターミナルで、EShop のルートから。上から順に試す）

        1) 通常
           .\tools\check-setup.ps1

        2) 「このシステムではスクリプトの実行が無効になっている」と出る場合
           powershell -ExecutionPolicy Bypass -File .\tools\check-setup.ps1

        3) 2でも同じエラーになる場合（グループポリシーで縛られているPC）
           & ([scriptblock]::Create((Get-Content .\tools\check-setup.ps1 -Raw)))

           実行ポリシーが禁じているのはスクリプトファイル（.ps1）の実行だけなので、
           中身を文字列として読み込んで実行するこの形は管理者権限なしで通る。
           引数を渡す場合は末尾に足す:
           & ([scriptblock]::Create((Get-Content .\tools\check-setup.ps1 -Raw))) -SkipTest

    出力されるファイル

        eshop-diagnose-<日時>.md   判定一覧・直し方・各項目の出力
                                   既定の置き場は EShop の親フォルダ（EShop の中には置かない。
                                   git status に出て、自分の成果物と混ざるため）
                                   1項目ごとに書き出すので、途中で止めても残る

    引数

        -EShopDir <path> 診断する EShop のフォルダ（既定はカレントから上へたどって見つける。
                         EShop の親フォルダで起動した場合は直下の EShop）
        -OutDir <path>   記録の出力先（既定は EShop の親フォルダ）
        -SkipTest        pytest を実行しない（約10秒短くなる）
#>

[CmdletBinding()]
param(
    [string]$EShopDir,
    [string]$OutDir,
    [switch]$SkipTest
)

$ErrorActionPreference = 'Continue'

function Get-ScriptVersion([string]$RepoDir) {
    # 版は実行時に git から読む。記録を読んだ人が、どの版で走らせた結果かを突き止められるようにする。
    # clone の中から実行したときは、このファイルを最後に変えたコミットを版とする。ファイル名と
    # 置き場は決め打ちせず、実行中のファイルが属するリポジトリのルートからの相対パスで引く。
    # 起動方法3では $PSCommandPath が空になるので、見つけた EShop の tools\check-setup.ps1 で引く。
    # 履歴から引けないとき（ファイルだけを取り出して実行した場合など）は、中身の blob ID を版とする。
    # hash-object は autocrlf の変換を通すので、checkout で改行が CRLF になっていても、追跡中の
    # blob と同じ値になる。
    # 版が読めなくても診断は続けたいので、どの経路でも例外で止めない。$ErrorActionPreference が
    # Continue でも git のエラー出力が画面に出ないよう、2>$null で捨てる。
    # PowerShell 7.3 以降でこれが有効だと、git の終了コードが 0 以外のときにエラーが画面に出る
    $PSNativeCommandUseErrorActionPreference = $false
    if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) { return '不明（gitが見つからない）' }
    $file = if ($PSCommandPath) { $PSCommandPath } elseif ($RepoDir) { Join-Path $RepoDir 'tools\check-setup.ps1' } else { $null }
    if (-not $file -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { return '不明（ファイルの場所が分からない）' }
    $dir = Split-Path $file -Parent
    $name = Split-Path $file -Leaf
    # git はパスを UTF-8 で出す。PowerShell 5.1 は CP932 として読むため、日本語を含むパスが化ける
    $prev = [Console]::OutputEncoding
    try {
        try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
        $top = "$(& git -C $dir rev-parse --show-toplevel 2>$null)".Trim()
        if ($LASTEXITCODE -eq 0 -and $top) {
            # ルートからの相対パス。show-prefix はカレント（ここでは置き場）のルートからの位置を返す
            $rel = "$(& git -C $dir rev-parse --show-prefix 2>$null)".Trim() + $name
            # %cs（コミット日）は古い git では展開されない。形が合わなければ blob ID に回す
            $log = "$(& git -C $top log -1 --format='%h %cs %H' -- $rel 2>$null)".Trim()
            if ($LASTEXITCODE -eq 0 -and $log -match '^([0-9a-f]{7,} \d{4}-\d{2}-\d{2}) ([0-9a-f]{40,})$') {
                $log = $Matches[1]
                $full = $Matches[2]
                # 浅い clone（--depth 1）では、境界のコミットがすべてのファイルを足したように見える。
                # このファイルを最後に変えたコミットまで履歴が届いていないと、境界（clone した時点の
                # コミット）が返るので、そうと分かるように書き添える
                $shallow = "$(& git -C $top rev-parse --is-shallow-repository 2>$null)".Trim()
                if ($shallow -eq 'true') {
                    $sf = "$(& git -C $top rev-parse --git-path shallow 2>$null)".Trim()
                    if ($sf -and -not [System.IO.Path]::IsPathRooted($sf)) { $sf = Join-Path $top $sf }
                    $bounds = @(if ($sf -and (Test-Path -LiteralPath $sf)) { Get-Content -LiteralPath $sf })
                    if ($bounds.Count -eq 0 -or $bounds -contains $full) { $log += '（浅い clone のため、clone した時点のコミット）' }
                }
                $st = "$(& git -C $top status --porcelain -- $rel 2>$null)".Trim()
                if ($st) { $log += ' ※未コミットの変更あり' }
                return $log
            }
        }
        $blob = "$(& git -C $dir hash-object -- $file 2>$null)".Trim()
        if ($LASTEXITCODE -eq 0 -and $blob -match '^[0-9a-f]{40,}$') { return "blob $($blob.Substring(0, 7))" }
    } catch {
    } finally {
        try { [Console]::OutputEncoding = $prev } catch { }
    }
    return '不明（gitから読み取れない）'
}

# PowerShellがネイティブコマンドの出力を解釈する文字コードに、Python側の出力を合わせる。
# Pythonはパイプ出力のときロケールの文字コード（日本語WindowsならCP932）で書くため、
# 揃えないと記録が文字化けし、件数の自動判定も誤る。
# [Console]::OutputEncoding は機材によって変わる（プロファイルでUTF-8にしてある機材は
# 65001、素のWindowsは932）。版では決まらないので、実際の値を読んで合わせる。
# 起動方法3ではターミナルの環境変数がそのまま残るので、終わったら元に戻す（起点を参照）。
$script:ConsoleCodePage = [Console]::OutputEncoding.CodePage
$script:PrevPythonIoEncoding = $env:PYTHONIOENCODING
$env:PYTHONIOENCODING = if ($script:ConsoleCodePage -eq 65001) { 'utf-8' } else { "cp$($script:ConsoleCodePage)" }

# ---------------------------------------------------------------- 表示ヘルパ

function Write-Rule([string]$char = '-') {
    Write-Host ($char * 78) -ForegroundColor DarkGray
}

function Write-Head([string]$text) {
    Write-Host ''
    Write-Rule '='
    Write-Host $text -ForegroundColor Cyan
    Write-Rule '='
}

function Get-MarkLabel([string]$Mark) {
    # 全角混在のため -4 の書式指定では揃わない。半角2文字のものだけ空白で埋める
    switch ($Mark) { 'OK' { 'OK  ' } 'NG' { 'NG  ' } default { $Mark } }
}

function Get-MarkColor([string]$Mark) {
    # 画面共有で読めるように、彩度ではなく明度で差をつける。Magenta は Campbell で
    # コントラスト 3.2:1 しかなく、Teams の圧縮でも最初に潰れるため使わない。
    switch ($Mark) {
        'OK' { 'Green' }
        'NG' { 'Red' }
        '注意' { 'Yellow' }      # 動くが手順書どおりでない
        '参考' { 'Gray' }
        default { 'DarkGray' }   # 未確認
    }
}

function Write-Mark([string]$Mark, [string]$Text) {
    # 判定を行頭に出す。色が落ちる画面や記録でも、読み飛ばしてよい行とここで止まる行が
    # 見分けられるようにするため。幅を揃えて後続の説明行とぶら下げを合わせる。
    Write-Host ('  {0}  {1}' -f (Get-MarkLabel $Mark), $Text) -ForegroundColor (Get-MarkColor $Mark)
}

function Remove-AnsiEscape([string]$Text) {
    # pytest などが色付けに使う制御シーケンスを外す。残すとmdが読めなくなる
    if (-not $Text) { return $Text }
    $esc = [char]27
    return ($Text -replace "$esc\[[0-9;?]*[ -/]*[@-~]", '' -replace "$esc\][^$esc]*($([char]7)|$esc\\)", '')
}

# ---------------------------------------------------------------- 診断の部品
#
# 受講者が作業中の環境なので、読み取りだけにする。直す操作は、表示した手順書の手順どおりに
# 受講者が行う。

$script:Checks = @()
$script:DxResults = @()
$script:DxFix = @()
$script:Dx = @{}

function New-Check {
    param([string]$Id, [string]$Group, [string]$Title, [string]$Ref, [scriptblock]$Cmd, [scriptblock]$Hint)
    $script:Checks += [pscustomobject]@{
        Id = $Id; Group = $Group; Title = $Title; Ref = $Ref
        Cmd = $Cmd; Hint = $Hint
    }
}

function Invoke-Check($Check) {
    # 出力を画面に出しながら控え、判定（Hint）に渡す
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $raw = $null
    Write-Rule
    try {
        & $Check.Cmd 2>&1 | Tee-Object -Variable raw | Out-Host
    } catch {
        Write-Host "  例外: $($_.Exception.Message)" -ForegroundColor Red
        $raw = @("例外: $($_.Exception.Message)")
    }
    $sw.Stop()
    Write-Rule
    $sec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Write-Host ("  所要 {0}秒" -f $sec) -ForegroundColor DarkGray
    $text = Remove-AnsiEscape ($raw | Out-String -Width 200)
    $suggest = $null
    if ($Check.Hint) {
        try { $suggest = & $Check.Hint $text } catch { }
    }
    if ($suggest) { $suggest = ("$suggest").Trim() }
    if ($suggest -and $suggest -notin 'OK', 'NG', '注意', '参考', '未確認') { $suggest = $null }
    return @{ Text = $text; Seconds = $sec; Suggest = $suggest }
}

function Write-Fix([string]$Text) {
    # 直し方。まとめと記録にも同じ文面を出すため控えておく
    $script:DxFix += $Text
    Write-Host "        → $Text" -ForegroundColor Yellow
}

function Find-EShopDir([string]$Start) {
    # カレントから上へたどり、backend\app\main.py があるフォルダを EShop とみなす。
    # clone した作業フォルダ（EShop の親）で起動した場合に備えて、起点の直下の EShop も見る。
    $d = (Resolve-Path -LiteralPath $Start -ErrorAction SilentlyContinue).Path
    if (-not $d) { return $null }
    $child = Join-Path $d 'EShop'
    if (-not (Test-Path (Join-Path $d 'backend\app\main.py')) -and (Test-Path (Join-Path $child 'backend\app\main.py'))) {
        return $child
    }
    while ($d) {
        if (Test-Path (Join-Path $d 'backend\app\main.py')) { return $d }
        $parent = Split-Path $d -Parent
        if (-not $parent -or $parent -eq $d) { break }
        $d = $parent
    }
    return $null
}

function Read-DxExpect([string]$RepoDir) {
    # ブランチごとに違う期待値（ブランチ名・段階・要るファイルとテーブル・テストの件数など）は
    # tools\check-setup.json に置く。本文をどのブランチでも同じにしておき、違いをこのファイル
    # だけに出すため。起動方法3でも読めるよう、見つけた EShop のルートから引く。
    # 読めなくてもほかの項目は診断したいので、例外で止めず、理由を Error に入れて返す
    $f = Join-Path $RepoDir 'tools\check-setup.json'
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { return @{ Error = 'tools\check-setup.json が無い' } }
    try {
        $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        # 例外の文面はファイルの中身を長く引用して読みにくいので、理由だけにする
        return @{ Error = 'tools\check-setup.json を JSON として読めない' }
    }
    if ($null -eq $j -or $j -isnot [System.Management.Automation.PSCustomObject]) { return @{ Error = 'tools\check-setup.json の形が違う' } }
    # 名前は Python の SQL にそのまま埋めるので、識別子の形だけを通す
    $ident = '^[A-Za-z_][A-Za-z0-9_]*$'
    $str = { param($v) ($v -is [string]) -and $v.Trim() }
    foreach ($k in 'branch', 'stage', 'seedStep') {
        if (-not (& $str $j.$k)) { return @{ Error = "tools\check-setup.json の $k が無い" } }
    }
    if ($j.changedCode -notin 'keep', 'debug') { return @{ Error = 'tools\check-setup.json の changedCode は keep か debug' } }
    $tests = 0
    if (-not [int]::TryParse("$($j.expectedTests)", [ref]$tests) -or $tests -lt 1) { return @{ Error = 'tools\check-setup.json の expectedTests が数でない' } }
    # テストの置き場（backend\tests の下のフォルダ。integration・unit）ごとの件数。表示に使い、判定は
    # 合計（expectedTests）で行う。無ければ内訳の基準は出さない。あれば合計と合っていること
    $byLevel = [ordered]@{}
    if ($null -ne $j.expectedTestsByLevel) {
        if ($j.expectedTestsByLevel -isnot [System.Management.Automation.PSCustomObject]) { return @{ Error = 'tools\check-setup.json の expectedTestsByLevel の形が違う' } }
        foreach ($p in $j.expectedTestsByLevel.PSObject.Properties) {
            $n = 0
            if ($p.Name -notmatch '^[a-z]+$' -or -not [int]::TryParse("$($p.Value)", [ref]$n) -or $n -lt 0) { return @{ Error = 'tools\check-setup.json の expectedTestsByLevel に使えない名前か数でない値がある' } }
            $byLevel[$p.Name] = $n
        }
        $sum = 0
        foreach ($v in $byLevel.Values) { $sum += $v }
        if ($sum -ne $tests) { return @{ Error = 'tools\check-setup.json の expectedTestsByLevel の合計が expectedTests と合わない' } }
    }
    $files =@($j.requiredFiles | Where-Object { $null -ne $_ } | ForEach-Object { "$_" })
    $tables = @($j.requiredTables | Where-Object { $null -ne $_ } | ForEach-Object { "$_" })
    if (@($tables | Where-Object { $_ -notmatch $ident }).Count -gt 0) { return @{ Error = 'tools\check-setup.json の requiredTables に使えない名前がある' } }
    $cols = @()
    if ($j.requiredColumns) {
        foreach ($p in $j.requiredColumns.PSObject.Properties) {
            foreach ($c in @($p.Value | Where-Object { $null -ne $_ } | ForEach-Object { "$_" })) {
                if ($p.Name -notmatch $ident -or $c -notmatch $ident) { return @{ Error = 'tools\check-setup.json の requiredColumns に使えない名前がある' } }
                $cols += "$($p.Name).$c"
            }
        }
    }
    $docs = @()
    foreach ($d in @($j.requiredDocs | Where-Object { $null -ne $_ })) {
        if (-not (& $str $d.path) -or -not (& $str $d.message) -or -not (& $str $d.fix)) { return @{ Error = 'tools\check-setup.json の requiredDocs には path・message・fix が要る' } }
        $docs += [pscustomobject]@{ Path = $d.path; Message = $d.message; Fix = $d.fix }
    }
    return @{
        Error = $null
        Branch = $j.branch.Trim(); Stage = $j.stage.Trim(); SeedStep = $j.seedStep.Trim()
        SwitchStep = $(if (& $str $j.switchStep) { $j.switchStep.Trim() } else { $null })
        ChangedCode = $j.changedCode; ExpectedTests = $tests; ExpectedByLevel = $byLevel
        Files = $files; Docs = $docs; Tables = $tables; Columns = $cols
        TestFailFix = @($j.testFailFix | Where-Object { & $str $_ })
    }
}

function Invoke-DxGit {
    # git はパスを UTF-8 で出す。PowerShell 5.1 はネイティブの出力を CP932 として読むため、
    # docs\基本設計書.md のような日本語のファイル名が化ける。この間だけ UTF-8 で読む。
    $prev = [Console]::OutputEncoding
    try {
        try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
        # 改行コードの警告（LF will be replaced by CRLF）が標準エラーに混ざり、ファイルの一覧に
        # 紛れ込むので落とす
        & git -C $script:Dx.Repo -c core.quotepath=false @args 2>&1 | ForEach-Object { "$_" } |
            Where-Object { $_ -notmatch '^warning: ' }
    } finally {
        try { [Console]::OutputEncoding = $prev } catch { }
    }
}

function Get-DxPython {
    $p = Join-Path $script:Dx.Src '.venv\Scripts\python.exe'
    if (Test-Path $p) { return $p }
    return $null
}

function Get-DxRestoreFix([string[]]$Paths) {
    # 書き換えた・消した既存テストを戻すコマンド。テストは backend\tests の下のフォルダ
    # （integration・unit）に分かれているので、変わったファイルを backend からのパスでそのまま出す
    $rel = @($Paths | Where-Object { $_ -match '^backend/tests/' } | ForEach-Object { $_ -replace '^backend/', '' } | Select-Object -Unique)
    if ($rel.Count -eq 0) { $rel = @('tests/<フォルダ>/<ファイル名>') }
    return "git restore $($rel -join ' ')"
}

function Get-DxTestLevel([string]$Path) {
    # テストの置き場（backend/tests/<フォルダ>/test_*.py のフォルダ名）。tests の直下なら空
    if ($Path -match '^backend/tests/([^/]+)/test_[^/]*\.py$') { return $Matches[1] }
    return ''
}

function Get-DxTestLevelLabel([string]$Level) {
    switch ($Level) {
        'integration' { '結合テスト（integration）' }
        'unit' { '単体テスト（unit）' }
        '' { 'tests の直下' }
        default { $Level }
    }
}

function Invoke-DxPython([string]$Python, [string]$Code, [string[]]$Arguments) {
    # コードは ASCII だけで書く。PowerShell 5.1 はネイティブへ渡す標準入力を ASCII で書くため、
    # 日本語を混ぜると化ける。引数（パス）はコマンドラインで渡るので日本語でもよい。
    # バイトコード（__pycache__）を書かせない。作業ツリーを変えないため
    $prevB = $env:PYTHONDONTWRITEBYTECODE
    $env:PYTHONDONTWRITEBYTECODE = '1'
    try {
        $Code | & $Python - @Arguments 2>&1 | ForEach-Object { "$_" }
    } finally {
        $env:PYTHONDONTWRITEBYTECODE = $prevB
    }
}

# ---------------------------------------------------------------- 診断の項目

function Set-CheckList {

    # ====================== 道具 ======================

    New-Check -Id 'D1-1' -Group '道具' -Title 'Python' -Ref '01-01 前提条件・手順2' -Cmd {
        $all = @(Get-Command python -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
        if ($all.Count -eq 0) { 'python => このターミナルから見つからない'; return }
        $all | ForEach-Object { "python => $_" }
        $v = try { & $all[0] --version 2>&1 | ForEach-Object { "$_" } } catch { "起動できない: $($_.Exception.Message)" }
        "版     => $v"
    } -Hint {
        param($text)
        if ($text -match 'Python\s+3\.(\d+)') {
            $minor = [int]$Matches[1]
            if ($minor -ge 11) { Write-Mark 'OK' "3.$minor（3.11以上）"; return 'OK' }
            Write-Mark 'NG' "3.$minor。3.11以上が要る"
            Write-Fix '3.11以上のPythonを入れる必要がある。講師に申し出る'
            return 'NG'
        }
        if ($text -match 'WindowsApps') { Write-Mark 'NG' 'Microsoft Store の案内用のpython（中身が無い）しか見つからない' }
        else { Write-Mark 'NG' 'pythonが見つからない、または起動できない' }
        Write-Fix 'Pythonが入っていない。講師に申し出る'
        return 'NG'
    }

    New-Check -Id 'D1-2' -Group '道具' -Title 'Git' -Ref '01-01 前提条件' -Cmd {
        $v = try { git --version 2>&1 | ForEach-Object { "$_" } } catch { $null }
        if ($v) { $v } else { 'gitが見つからない' }
    } -Hint {
        param($text)
        if ($text -match 'git version') { Write-Mark 'OK' '入っている'; return 'OK' }
        Write-Mark 'NG' 'gitが見つからない'
        Write-Fix 'Gitが入っていない。講師に申し出る'
        return 'NG'
    }

    New-Check -Id 'D1-3' -Group '道具' -Title 'Claude Code（CLI）' -Ref '01-02 手順2' -Cmd {
        $bin = Join-Path $env:USERPROFILE '.local\bin'
        # 実行ファイルを先に探す。npm 版の claude.ps1 を拾うと、実行ポリシーが Restricted の PC では
        # 版を取るところで弾かれ、「PATH に無い」と誤って判定するため
        $c = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $c) { $c = Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1 }
        if ($c) {
            "claude => $($c.Source)"
            $v = try { & $c.Source --version 2>&1 | ForEach-Object { "$_" } } catch { "起動できない: $($_.Exception.Message)" }
            "版     => $v"
        } else {
            'claude => このターミナルから見つからない'
        }
        $exe = Join-Path $bin 'claude.exe'
        "実体   => $(if (Test-Path $exe) { $exe } else { '既定の置き場（.local\bin）に無い' })"
        $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
        "User PATH への登録 => $(if (($userPath -split ';') -contains $bin) { 'あり' } else { 'なし' })"
    } -Hint {
        param($text)
        if ($text -match '版\s+=>\s*\S*\d+\.\d+') {
            if ($text -match 'claude => .*\\\.local\\bin\\' -and $text -match 'User PATH への登録 => なし') {
                Write-Mark '注意' 'このターミナルでは使えるが、User PATH に登録されていない。開き直すと見つからなくなる'
                Write-Fix '01-02 手順2 の「claude の置き場を PATH に追加する」コマンドを実行する'
                return '注意'
            }
            Write-Mark 'OK' '使える'
            return 'OK'
        }
        if ($text -match '実体\s+=> .*claude\.exe') {
            Write-Mark 'NG' 'インストールはされているが、このターミナルから見つからない'
            Write-Fix '01-02 手順2 の「claude の置き場を PATH に追加する」コマンドを最後の行まで実行する'
        } else {
            Write-Mark 'NG' 'インストールされていない'
            Write-Fix '01-02 手順2 のインストールからやり直す。エラーが出たら講師に申し出る'
        }
        return 'NG'
    }

    New-Check -Id 'D1-4' -Group '道具' -Title 'VS Code拡張（Claude Code for VS Code）' -Ref '01-02 手順3' -Cmd {
        $code = Get-Command code -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $code) { 'code => 見つからない（拡張の一覧を取れない）'; return }
        $raw = @(& code --list-extensions --show-versions 2>&1 | ForEach-Object { "$_" })
        $cl = @($raw | Where-Object { $_ -match '(?i)^anthropic\.claude-code@' })
        "Claude拡張 => $(if ($cl.Count -gt 0) { $cl -join ' ' } else { '入っていない' })"
    } -Hint {
        param($text)
        if ($text -match '(?i)anthropic\.claude-code@') { Write-Mark 'OK' '入っている'; return 'OK' }
        if ($text -match 'code => 見つからない') {
            Write-Mark '未確認' 'code コマンドが無いため調べられない（講座では code コマンドは使わないので問題ない）'
            Write-Host '        VS Code の拡張機能ビューで「Claude Code for VS Code」が入っているかを目で確かめる' -ForegroundColor DarkGray
            return '未確認'
        }
        Write-Mark 'NG' '拡張が入っていない'
        Write-Fix '01-02 手順3: 拡張機能ビューで「Claude Code for VS Code」をインストールし、Sign in する'
        return 'NG'
    }

    New-Check -Id 'D1-5' -Group '道具' -Title '実行ポリシー（activate が使えるか）' -Ref '01-01 手順2' -Cmd {
        $list = try { @(Get-ExecutionPolicy -List -ErrorAction Stop) } catch { @() }
        if ($list.Count -eq 0) {
            # PowerShell 7 から 5.1 を起動した場合など、モジュールを読めずに Get-ExecutionPolicy が
            # 使えないことがある。同じ値をレジストリから読む
            'Get-ExecutionPolicy が使えないため、レジストリから読む'
            $map = [ordered]@{
                'MachinePolicy' = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell'
                'UserPolicy'    = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\PowerShell'
                'CurrentUser'   = 'HKCU:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'
                'LocalMachine'  = 'HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'
            }
            $list = foreach ($k in $map.Keys) {
                $v = (Get-ItemProperty -Path $map[$k] -Name ExecutionPolicy -ErrorAction SilentlyContinue).ExecutionPolicy
                [pscustomobject]@{ Scope = $k; ExecutionPolicy = $(if ($v) { $v } else { 'Undefined' }) }
            }
        }
        foreach ($e in $list) { '{0,-14} {1}' -f $e.Scope, $e.ExecutionPolicy }
        # ターミナルを開き直したときの実効値。Process スコープは起動のしかた（-ExecutionPolicy
        # Bypass など）で変わり、受講者のターミナルを表さないので除いて決める
        $eff = 'Restricted'
        foreach ($s in 'MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine') {
            $v = "$(($list | Where-Object { "$($_.Scope)" -eq $s }).ExecutionPolicy)"
            if ($v -and $v -ne 'Undefined') { $eff = $v; break }
        }
        "ターミナルを開いたときの実効値 => $eff"
    } -Hint {
        param($text)
        if ($text -match '実効値 => (RemoteSigned|Unrestricted|Bypass)') { Write-Mark 'OK' 'activate（.venv\Scripts\activate）が使える'; return 'OK' }
        if ($text -match '取得できない') { Write-Mark '未確認' '実行ポリシーを取得できない'; return '未確認' }
        if ($text -match '(?m)^\s*(MachinePolicy|UserPolicy)\s+(?!Undefined)\S+') {
            Write-Mark '注意' '会社のポリシーで制限されている。activate はエラーになる'
            Write-Fix '01-01 手順2 の代替の1行（$env:VIRTUAL_ENV=...）で有効にする。ターミナルを開き直すたびに必要'
        } else {
            Write-Mark '注意' 'このままでは activate がエラーになる'
            Write-Fix '01-01 手順2 の Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser を実行してから activate する'
        }
        return '注意'
    }

    # ====================== リポジトリ ======================

    New-Check -Id 'D2-1' -Group 'リポジトリ' -Title 'EShop の場所と clone 元' -Ref '01-01 手順1' -Cmd {
        "EShop    => $($script:Dx.Repo)"
        "カレント => $((Get-Location).Path)"
        "clone元  => $(@(Invoke-DxGit remote get-url origin) -join ' ')"
    } -Hint {
        param($text)
        $r = 'OK'
        if ($text -notmatch '(?i)SEC-Online-Boot-Camp/EShop') {
            Write-Mark '注意' 'clone元が講座のリポジトリになっていない'
            Write-Fix '01-01 手順1 のURLで clone したフォルダかを講師と確かめる'
            $r = '注意'
        }
        if ($script:Dx.Repo -match '(?i)OneDrive') {
            Write-Mark '注意' 'OneDrive の同期対象の中にある。.venv の作成や pip install が遅くなったり失敗したりする'
            Write-Fix '動いていれば移動は不要。失敗が続くときは講師に申し出る（OneDrive の外に clone し直す）'
            $r = '注意'
        }
        if ($r -eq 'OK') { Write-Mark 'OK' '講座のリポジトリを clone したフォルダ' }
        return $r
    }

    New-Check -Id 'D2-2' -Group 'リポジトリ' -Title 'ブランチと作業の状態' -Ref '03-01 手順1' -Cmd {
        $br = $script:Dx.Branch
        "ブランチ   => $(if ($br) { $br } else { '（どのブランチにもいない）' })"
        $gd = @(Invoke-DxGit rev-parse --git-dir)[0]
        $gdPath = if ([System.IO.Path]::IsPathRooted($gd)) { $gd } else { Join-Path $script:Dx.Repo $gd }
        $ops = @()
        if (Test-Path (Join-Path $gdPath 'MERGE_HEAD')) { $ops += 'merge' }
        if ((Test-Path (Join-Path $gdPath 'rebase-merge')) -or (Test-Path (Join-Path $gdPath 'rebase-apply'))) { $ops += 'rebase' }
        if (Test-Path (Join-Path $gdPath 'CHERRY_PICK_HEAD')) { $ops += 'cherry-pick' }
        "途中の操作 => $(if ($ops.Count -gt 0) { $ops -join ', ' } else { 'なし' })"
        "比べる相手 => $($script:Dx.Base)（配布された状態）"
        # 作業ツリーと配布された状態の差。No.4 は git add -A するので、コミットしていても拾えるようにする
        $diff = @(Invoke-DxGit diff --name-status $script:Dx.Base '--' backend/app backend/tests | Where-Object { $_ })
        '--- 配布された状態から変わった backend/app・backend/tests ---'
        if ($diff.Count -gt 0) { $diff | ForEach-Object { "  $_" } } else { '  （なし）' }
        # No.2 で作る・追記するファイルは、あるかどうかだけを見る（中身は見ない）
        $docs = @(Get-ChildItem (Join-Path $script:Dx.Repo 'docs') -Filter *.md -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        "docs       => $(if ($docs.Count -gt 0) { $docs -join ', ' } else { '無い' })"
        # 基本設計書.md は、配布された状態から変わったかも出す。表示だけで、判定には使わない。
        # 追記する回があるので、変わっていても普通。中身は見ず、git diff の終了コードだけを見る
        $bd = '無い'
        if (Test-Path (Join-Path $script:Dx.Repo 'docs\基本設計書.md')) {
            $null = @(Invoke-DxGit diff --quiet $script:Dx.Base '--' docs/基本設計書.md)
            $bd = switch ($LASTEXITCODE) { 0 { 'あり（配布された状態のまま）' } 1 { 'あり（変更あり）' } default { 'あり（比べられない）' } }
        }
        "基本設計書.md => $bd"
        # 自分の設計を写したファイル（基本設計書_<氏名>.md）。これも表示だけ
        $own = @(Get-ChildItem (Join-Path $script:Dx.Repo 'docs') -Filter '基本設計書_*.md' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        "基本設計書_*.md => $(if ($own.Count -gt 0) { $own -join ', ' } else { '無い' })"
        "要望メモ.md   => $(if (Test-Path (Join-Path $script:Dx.Repo 'docs\要望メモ.md')) { 'あり' } else { '無い' })"
        "要件整理.md   => $(if (Test-Path (Join-Path $script:Dx.Repo 'docs\要件整理.md')) { 'あり' } else { '無い' })"
        # この段階で要るファイル（期待値の requiredFiles）。名前は期待値から引き、本文には書かない
        $ex = $script:Dx.Expect
        if ($ex.Error) { "必須ファイル => 未確認（$($ex.Error)）" }
        elseif ($ex.Files.Count -eq 0) { '必須ファイル => （この段階には無い）' }
        else {
            foreach ($f in $ex.Files) {
                "必須ファイル => ${f}: $(if (Test-Path -LiteralPath (Join-Path $script:Dx.Repo ($f -replace '/', '\'))) { 'あり' } else { 'なし' })"
            }
        }
    } -Hint {
        param($text)
        $br = $script:Dx.Branch
        $ex = $script:Dx.Expect
        if ($text -match '基本設計書\.md => 無い') {
            Write-Mark 'NG' 'docs\基本設計書.md が無い（配布時から入っていて、No.2 で追記するファイル）'
            Write-Fix '名前を変えたなら元の名前に戻す。消した場合は、自分で戻さず講師に申し出る'
            return 'NG'
        }
        if ($text -match '途中の操作 => (?!なし)') {
            Write-Mark 'NG' 'git の操作（merge・rebase など）が途中で止まっている'
            Write-Fix '自分で直さず講師に申し出る（手元の変更を失わないようにするため）'
            return 'NG'
        }
        if (-not $br) {
            Write-Mark 'NG' 'どのブランチにもいない（detached HEAD）'
            Write-Fix '自分で直さず講師に申し出る（手元の変更を失わないようにするため）'
            return 'NG'
        }
        $lines = @($text -split "`n" | Where-Object { $_ -match '^\s+[AMDR]\d*\s+backend/' })
        $app = @($lines | Where-Object { $_ -match 'backend/app/' })
        # 追加（A）は自分で作ったテスト。問題になるのは既存のテストを変えた・消した場合
        $tests = @($lines | Where-Object { $_ -match '^\s+[MDR]\d*\s+backend/tests/' })
        # ここから先はブランチごとの判定。期待値（tools\check-setup.json）が読めなければ確かめない
        if ($ex.Error) {
            Write-Mark '未確認' "ブランチの状態は確かめていない。期待値を読めないため（$($ex.Error)）"
            Write-Host '        tools\check-setup.json は配布時から入っている。消した・変えた場合は講師に申し出る' -ForegroundColor DarkGray
            return '未確認'
        }
        if ($br -ne $ex.Branch) {
            Write-Mark '注意' "手順書に無いブランチ（$br）にいる"
            Write-Fix "この EShop の段階（$($ex.Stage)）では $($ex.Branch) を使う。切り替える前に講師に申し出る"
            return '注意'
        }
        $r = 'OK'
        Write-Mark '参考' "$br ブランチ（$($ex.Stage)の状態）"
        $lost = @([regex]::Matches($text, '(?m)^必須ファイル => (.+): なし\s*$') | ForEach-Object { $_.Groups[1].Value.Trim() })
        if ($lost.Count -gt 0) {
            Write-Mark 'NG' "$br ブランチなのに $(($lost | ForEach-Object { $_ -replace '/', '\' }) -join '・') が無い"
            $step = if ($ex.SwitchStep) { "$($ex.SwitchStep) の" } else { 'ブランチの' }
            Write-Fix "講師に申し出る（${step}切り替えが途中で止まっている可能性がある）"
            return 'NG'
        }
        foreach ($d in $ex.Docs) {
            if (-not (Test-Path -LiteralPath (Join-Path $script:Dx.Repo ($d.Path -replace '/', '\')))) {
                Write-Mark '注意' $d.Message
                Write-Fix $d.Fix
                $r = '注意'
            }
        }
        if ($ex.ChangedCode -eq 'keep') {
            # コードを変えない段階。配布されたコードが変わっていれば、後の段階のテストが崩れる
            if ($app.Count -gt 0 -or $tests.Count -gt 0) {
                Write-Mark '注意' '配布されたコード（backend/app・backend/tests）が変わっている'
                Write-Fix "$($ex.Stage) ではコードを変えない。No.3 で pytest が失敗する原因になるので、講師と一緒に上の一覧を確かめる"
                $r = '注意'
            }
        } else {
            # デバッグでコードを直す段階。既存のテストだけは変えない
            if ($tests.Count -gt 0) {
                Write-Mark '注意' '配布された既存のテストが書き換えられている'
                # 名前を変えた（R）ときは元のパス（行の最初のパス）を戻す
                $paths = @($tests | ForEach-Object { @($_.Trim() -split '\s+' | Where-Object { $_ -match '^backend/tests/' })[0] })
                Write-Fix "03-03 手順2: backend で $(Get-DxRestoreFix $paths) で戻す"
                $r = '注意'
            }
            if ($app.Count -gt 0) {
                Write-Mark '参考' 'backend/app を変えている（03-04 のデバッグで直した分なら問題ない）'
            }
        }
        if ($r -eq 'OK') { Write-Mark 'OK' '手順書どおりの状態' }
        return $r
    }

    New-Check -Id 'D2-3' -Group 'リポジトリ' -Title '.env（値は表示しない）' -Ref '01-04 手順3' -Cmd {
        $f = Join-Path $script:Dx.Src '.env'
        if (-not (Test-Path $f)) { 'backendの.env => 無い'; return }
        $keys = @()
        $db = $null
        foreach ($line in (Get-Content -LiteralPath $f -Encoding UTF8)) {
            if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
                $keys += $Matches[1]
                if ($Matches[1] -eq 'DATABASE_URL') { $db = $Matches[2].Trim().Trim('"').Trim("'") }
            }
        }
        "キー         => $($keys -join ', ')"
        $form = if ($null -eq $db) { '行が無い' }
                elseif ($db -match '^sqlite:///') { 'sqlite:/// で始まる（配布時の形）' }
                elseif (-not $db) { '値が空' }
                else { 'sqlite:/// 以外に書き換えられている' }
        "DATABASE_URL => $form"
        $changed = @(Invoke-DxGit diff --name-only HEAD '--' backend/.env | Where-Object { $_ })
        "配布時からの変更 => $(if ($changed.Count -gt 0) { 'あり（01-04 の抽象化）' } else { 'なし' })"
    } -Hint {
        param($text)
        if ($text -match '\.env => 無い') {
            Write-Mark '注意' 'backend\.env が無い。アプリは警告を出して動くが、01-04 の演習ができない'
            Write-Fix '講師に申し出る（消した場合は backend で git restore .env で戻せる）'
            return '注意'
        }
        if ($text -match 'DATABASE_URL => (値が空|sqlite:/// 以外)') {
            Write-Mark 'NG' 'DATABASE_URL が配布時の形でない。サーバーの起動と pytest が失敗する'
            Write-Fix '01-04 手順3: DATABASE_URL はプレースホルダーにしない。DATABASE_URL=sqlite:///./ecommerce.db に戻す'
            return 'NG'
        }
        if ($text -match 'DATABASE_URL => 行が無い') {
            Write-Mark '注意' 'DATABASE_URL の行が無い（アプリは既定の sqlite:///./ecommerce.db で動く）'
            Write-Fix '01-04 手順3: DATABASE_URL の行は置き換えずに残す'
            return '注意'
        }
        Write-Mark 'OK' 'DATABASE_URL は配布時の形のまま'
        return 'OK'
    }

    # ====================== Python環境 ======================

    New-Check -Id 'D3-1' -Group 'Python環境' -Title '仮想環境（backend\.venv）' -Ref '01-01 手順2' -Cmd {
        $py = Join-Path $script:Dx.Src '.venv\Scripts\python.exe'
        "backendの.venv => $(if (Test-Path $py) { 'あり' } else { '無い' })"
        if (Test-Path $py) {
            $v = try { & $py --version 2>&1 | ForEach-Object { "$_" } } catch { "起動できない: $($_.Exception.Message)" }
            "版            => $v"
            $cfg = Join-Path $script:Dx.Src '.venv\pyvenv.cfg'
            if (Test-Path $cfg) {
                $base = ((Get-Content -LiteralPath $cfg | Where-Object { $_ -match '^\s*home\s*=' }) -replace '^\s*home\s*=\s*', '') | Select-Object -First 1
                "作成元        => $base$(if ($base -and -not (Test-Path $base)) { '（見つからない。アンインストール・移動された）' })"
            }
        }
        "EShop直下の.venv => $(if (Test-Path (Join-Path $script:Dx.Repo '.venv')) { 'あり' } else { 'なし' })"
    } -Hint {
        param($text)
        if ($text -match 'backendの\.venv => 無い') {
            Write-Mark 'NG' 'backend に仮想環境が無い'
            Write-Fix '01-01 手順2: backend で python -m venv .venv を実行し、有効化して pip install -r requirements.txt'
            if ($text -match 'EShop直下の\.venv => あり') {
                Write-Host '        EShop 直下に .venv がある。backend へ移動する前に作ったもので、使わない' -ForegroundColor Yellow
            }
            return 'NG'
        }
        if ($text -notmatch '版\s+=> Python 3') {
            Write-Mark 'NG' '仮想環境の python が起動しない（作成元の Python が消えた・動かされた など）'
            Write-Fix 'backend で Remove-Item -Recurse -Force .venv を実行し、01-01 手順2 の仮想環境の作成からやり直す'
            return 'NG'
        }
        if ($text -match 'EShop直下の\.venv => あり') {
            Write-Mark '注意' 'EShop 直下にも .venv がある（backend へ移動する前に作ったもの）。使うのは backend\.venv'
            Write-Fix '有効にしているのが backend\.venv かを D3-2 で確かめる。EShop 直下の .venv は使わない'
            return '注意'
        }
        Write-Mark 'OK' 'backend\.venv があり、起動できる'
        return 'OK'
    }

    New-Check -Id 'D3-2' -Group 'Python環境' -Title 'このターミナルでの有効化' -Ref '01-01 手順2' -Cmd {
        "VIRTUAL_ENV => $(if ($env:VIRTUAL_ENV) { $env:VIRTUAL_ENV } else { '（未設定＝有効になっていない）' })"
        foreach ($c in 'python', 'pip', 'pytest', 'uvicorn') {
            $s = (Get-Command $c -ErrorAction SilentlyContinue | Select-Object -First 1).Source
            '{0,-8}   => {1}' -f $c, $(if ($s) { $s } else { '見つからない' })
        }
    } -Hint {
        param($text)
        $venv = [System.IO.Path]::GetFullPath((Join-Path $script:Dx.Src '.venv')).TrimEnd('\')
        if (-not $env:VIRTUAL_ENV) {
            Write-Mark '注意' 'このターミナルでは仮想環境が有効になっていない'
            Write-Fix '01-01 手順2: backend で .venv\Scripts\activate（実行許可エラーになるPCは代替の1行）。ターミナルを開き直したら毎回必要'
            return '注意'
        }
        $now = try { [System.IO.Path]::GetFullPath($env:VIRTUAL_ENV).TrimEnd('\') } catch { $env:VIRTUAL_ENV }
        if ($now -ne $venv) {
            Write-Mark '注意' '別の仮想環境が有効になっている（backend\.venv ではない）'
            Write-Fix 'deactivate を実行してから、backend で .venv\Scripts\activate をやり直す'
            return '注意'
        }
        foreach ($c in 'python', 'pytest', 'uvicorn') {
            $s = (Get-Command $c -ErrorAction SilentlyContinue | Select-Object -First 1).Source
            if (-not $s -or -not $s.StartsWith($venv, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Mark '注意' "$c が仮想環境の外を指している（または見つからない）"
                Write-Fix '仮想環境を有効にした状態で、backend で pip install -r requirements.txt を実行する'
                return '注意'
            }
        }
        Write-Mark 'OK' 'backend\.venv が有効で、python・pytest・uvicorn がその中を指している'
        return 'OK'
    }

    New-Check -Id 'D3-3' -Group 'Python環境' -Title '依存パッケージ（requirements.txt との一致）' -Ref '01-01 手順2' -Cmd {
        $py = Get-DxPython
        if (-not $py) { '仮想環境が無いため確認しない'; return }
        # requirements.txt の「名前==版」を、仮想環境に入っている版と突き合わせる（pip は使わない）
        $code = @'
import re, sys
from importlib import metadata
bad = 0
for raw in open(sys.argv[1], encoding="utf-8"):
    line = raw.split("#", 1)[0].strip()
    m = re.match(r"([A-Za-z0-9_.-]+)(\[[^\]]*\])?==([^\s;]+)", line)
    if not m:
        continue
    name, want = m.group(1), m.group(3)
    try:
        have = metadata.version(name)
    except metadata.PackageNotFoundError:
        have = None
    ok = have == want
    bad += 0 if ok else 1
    print("%s  %-22s want %-10s have %s" % ("OK" if ok else "NG", name, want, have or "-"))
print("mismatch: %d" % bad)
'@
        Invoke-DxPython $py $code @((Join-Path $script:Dx.Src 'requirements.txt'))
    } -Hint {
        param($text)
        if ($text -match '仮想環境が無い') { Write-Mark '未確認' '仮想環境が無い（D3-1）'; return '未確認' }
        if ($text -match 'mismatch: (\d+)') {
            $n = [int]$Matches[1]
            if ($n -eq 0) { Write-Mark 'OK' 'requirements.txt の版がすべて入っている'; return 'OK' }
            Write-Mark 'NG' "requirements.txt と違う・入っていないパッケージが $n 件ある（上の NG の行）"
            Write-Fix '01-01 手順2: 仮想環境を有効にして、backend で pip install -r requirements.txt。エラーが出たら講師に見せる'
            return 'NG'
        }
        Write-Mark 'NG' '確認用のスクリプトが動かなかった（上の出力を講師に見せる）'
        return 'NG'
    }

    # ====================== データベース ======================

    New-Check -Id 'D4-1' -Group 'データベース' -Title '初期データ（backend\ecommerce.db）' -Ref '01-01 手順3・03-01 手順2' -Cmd {
        $py = Get-DxPython
        if (-not $py) { $py = (Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
        if (-not $py) { 'python が無いため確認しない'; return }
        # 読み取り専用で開く（mode=ro）。サーバーが起動中でも中身を変えない。
        # ファイルが無いときは開かない（開くと空の DB ができてしまう）。
        # 表示するテーブルと列は、期待値（tools\check-setup.json）に書いたものだけ。それ以外は数だけを
        # 出す（別の段階で作った DB でも、この段階で使わない名前を画面に出さない）。
        # users・products は件数の判定に使うので、期待値が読めなくても数える。
        # PowerShell 5.1 は空の引数を落とすので、空は - で渡す
        $code = @'
import os, pathlib, sqlite3, sys
def split(s):
    return [x for x in s.split(",") if x and x != "-"]
def main(p, want_t, want_c):
    if not os.path.exists(p):
        print("db: missing")
        return
    print("db: exists (%d bytes)" % os.path.getsize(p))
    try:
        con = sqlite3.connect(pathlib.Path(p).resolve().as_uri() + "?mode=ro", uri=True)
        names = set(r[0] for r in con.execute("select name from sqlite_master where type='table'")
                    if not r[0].startswith("sqlite_"))
        if want_t:
            print("tables: " + ", ".join(t for t in want_t if t in names))
            print("missing tables: " + (", ".join(t for t in want_t if t not in names) or "none"))
            print("other tables: %d" % len(names - set(want_t)))
        for t in want_t + [t for t in ("users", "products") if t not in want_t]:
            if t in names:
                print("count %s: %d" % (t, con.execute('select count(*) from "%s"' % t).fetchone()[0]))
        if want_c:
            have, lost = [], []
            for tc in want_c:
                t, c = tc.split(".", 1)
                cols = [r[1] for r in con.execute('pragma table_info("%s")' % t)] if t in names else []
                (have if c in cols else lost).append(tc)
            print("columns: " + ", ".join(have))
            print("missing columns: " + (", ".join(lost) or "none"))
        con.close()
    except Exception as e:
        print("error: %s" % e)

main(sys.argv[1], split(sys.argv[2]), split(sys.argv[3]))
'@
        $ex = $script:Dx.Expect
        $wantT = if (-not $ex.Error -and $ex.Tables.Count -gt 0) { $ex.Tables -join ',' } else { '-' }
        $wantC = if (-not $ex.Error -and $ex.Columns.Count -gt 0) { $ex.Columns -join ',' } else { '-' }
        Invoke-DxPython $py $code @((Join-Path $script:Dx.Src 'ecommerce.db'), $wantT, $wantC)
        "EShop直下の ecommerce.db => $(if (Test-Path (Join-Path $script:Dx.Repo 'ecommerce.db')) { 'あり' } else { 'なし' })"
    } -Hint {
        param($text)
        $ex = $script:Dx.Expect
        # seed の手順はブランチで違うので期待値から引く。読めなければ両方を挙げる
        $seed = if ($ex.Error) { '01-01 手順3・03-01 手順2 のうち、いまの段階のもの' } else { $ex.SeedStep }
        if ($text -match 'python が無い') { Write-Mark '未確認' 'python が無い（D1-1）'; return '未確認' }
        if ($text -match 'EShop直下の ecommerce\.db => あり') {
            Write-Mark '参考' 'EShop 直下にも ecommerce.db がある。backend 以外で seed を実行したもので、使われない'
        }
        if ($text -match 'db: missing') {
            Write-Mark 'NG' 'backend に ecommerce.db が無い（初期データを入れていない）'
            Write-Fix "${seed}: backend で python -m app.seed"
            return 'NG'
        }
        if ($text -match '(?m)^error:') {
            Write-Mark 'NG' 'DB を読めない（壊れている可能性がある）'
            Write-Fix 'サーバーを止めて、backend で Remove-Item ecommerce.db のあと python -m app.seed（中身は seed で作り直せる）'
            return 'NG'
        }
        # 期待値に書いたテーブル・列が DB に無ければ、前の段階で作った DB のまま。名前は Python が
        # 期待値から拾ったものだけが出る
        $lostT = if ($text -match '(?m)^missing tables: (.+?)\s*$' -and $Matches[1] -ne 'none') { @($Matches[1] -split ',\s*') } else { @() }
        $lostC = if ($text -match '(?m)^missing columns: (.+?)\s*$' -and $Matches[1] -ne 'none') { @($Matches[1] -split ',\s*') } else { @() }
        if ($lostT.Count + $lostC.Count -gt 0) {
            Write-Mark 'NG' "この段階で要るテーブル・列が DB に無い（$((@($lostT) + @($lostC)) -join '・')）。前の段階で作った DB のまま使っている"
            if ($lostC.Count -gt 0) {
                $t, $c = $lostC[0] -split '\.', 2
                Write-Host "        注文確定などで table $t has no column named $c のエラーになる" -ForegroundColor Yellow
            } else {
                Write-Host "        API が no such table: $($lostT[0]) のエラーになる" -ForegroundColor Yellow
            }
            Write-Fix "${seed}: サーバーを止めて、backend で Remove-Item ecommerce.db のあと python -m app.seed"
            return 'NG'
        }
        $u = if ($text -match 'count users: (\d+)') { [int]$Matches[1] } else { 0 }
        $p = if ($text -match 'count products: (\d+)') { [int]$Matches[1] } else { 0 }
        if ($u -lt 2 -or $p -lt 5) {
            Write-Mark '注意' "初期データが足りない（ユーザー${u}件・商品${p}件。seed はユーザー2件・商品5件）"
            Write-Fix "${seed}: サーバーを止めて、backend で Remove-Item ecommerce.db のあと python -m app.seed"
            return '注意'
        }
        if ($ex.Error) {
            Write-Mark '未確認' "初期データは入っているが、要るテーブル・列は確かめていない。期待値を読めないため（$($ex.Error)）"
            return '未確認'
        }
        # 判定には使わない。別の段階の seed で作った DB でも、要るものがそろっていれば動く
        if ($text -match '(?m)^other tables: [1-9]') {
            Write-Mark '参考' '別の段階で作った DB（この段階で使わないテーブルがある）。このまま使える'
        }
        Write-Mark 'OK' '初期データが入っている'
        return 'OK'
    }

    # ====================== サーバー ======================

    New-Check -Id 'D5-1' -Group 'サーバー' -Title '8000番とSwagger UI' -Ref '01-01 手順5' -Cmd {
        # サーバーは起動しない。起動中なら応答を見る（プロキシを通さずに 127.0.0.1 へ直接）
        $pids = @()
        # 実行ポリシーが Restricted の PowerShell 7 では、NetTCPIP モジュールを読み込めずに例外になる。
        # -ErrorAction では抑えられず、この項目がここで止まるので try で受ける
        try { $conns = @(Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction Stop) } catch { $conns = @() }
        if ($conns.Count -gt 0) {
            $pids = @($conns | ForEach-Object { $_.OwningProcess } | Sort-Object -Unique)
        } else {
            # Get-NetTCPConnection が使えない・モジュールを読み込めない機材に備えて、待ち受けられるかで確かめる
            $busy = $false
            try { $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 8000); $l.Start(); $l.Stop() } catch { $busy = $true }
            if (-not $busy) { '8000番 => 使われていない（サーバーは起動していない）'; return }
        }
        if ($pids.Count -eq 0) { '8000番 => 使用中（使っているアプリは調べられない）' }
        foreach ($id in $pids) {
            $pr = Get-Process -Id $id -ErrorAction SilentlyContinue
            "8000番 => 使用中: $($pr.ProcessName)  $($pr.Path)"
        }
        foreach ($u in '/docs', '/products') {
            $c = (curl.exe -s -o NUL -w "%{http_code}" --max-time 5 --noproxy '*' "http://127.0.0.1:8000$u" 2>&1)
            "GET $u => $c"
        }
    } -Hint {
        param($text)
        if ($text -match '使われていない') {
            Write-Mark 'OK' '8000番は空いている（サーバーは起動していない）'
            Write-Host '        起動するときは 01-01 手順5: backend で uvicorn app.main:app --reload' -ForegroundColor DarkGray
            return 'OK'
        }
        if ($text -match '使用中: (?!python)\S' -and $text -notmatch '使用中: python') {
            Write-Mark 'NG' '別のアプリが8000番を使っている'
            Write-Fix '講師に申し出る（そのアプリを止めるか、別の番号で起動する）'
            return 'NG'
        }
        if ($text -notmatch 'GET /docs => 200') {
            Write-Mark 'NG' 'サーバーは起動しているが応答しない'
            Write-Fix 'サーバーを起動したターミナルのエラーを講師に見せる。Ctrl+C で止めて起動し直す'
            return 'NG'
        }
        if ($text -notmatch 'GET /products => 200') {
            Write-Mark 'NG' 'Swagger UI は開けるが、商品一覧の API がエラーを返す（DB の問題が多い）'
            Write-Fix 'D4-1 の直し方を見る。サーバーを起動したターミナルのエラーも講師に見せる'
            return 'NG'
        }
        # どのフォルダのサーバーかは判定しない。venv の python.exe は実体の Python を別プロセスで
        # 起動するため、8000番を持つプロセスのパスは venv の外（作成元の Python）になる
        Write-Mark 'OK' 'サーバーが起動していて、Swagger UI と商品一覧が応答する'
        return 'OK'
    }

    # ====================== テスト ======================

    if (-not $SkipTest) {
        New-Check -Id 'D6-1' -Group 'テスト' -Title '配布されたテスト（pytest）' -Ref '01-01 手順4・03-01 手順2' -Cmd {
            $py = Get-DxPython
            if (-not $py) { '仮想環境が無いため実行しない'; return }
            # 実行するのは配布されたテストだけ。自分で作ったテストは演習の途中では失敗してよいので、
            # ここでは数えない
            # テストは tests の下のフォルダ（integration・unit）に分けて置いてある。tests の直下と、
            # その1つ下のフォルダの test_*.py を見る
            $dist = @(Invoke-DxGit ls-tree -r --name-only $script:Dx.Base '--' backend/tests |
                Where-Object { $_ -match '^backend/tests/([^/]+/)?test_[^/]*\.py$' })
            $testsDir = Join-Path $script:Dx.Src 'tests'
            $here = @(Get-ChildItem $testsDir -Filter 'test_*.py' -File -ErrorAction SilentlyContinue |
                ForEach-Object { "backend/tests/$($_.Name)" })
            foreach ($sub in @(Get-ChildItem $testsDir -Directory -ErrorAction SilentlyContinue)) {
                $here += @(Get-ChildItem $sub.FullName -Filter 'test_*.py' -File -ErrorAction SilentlyContinue |
                    ForEach-Object { "backend/tests/$($sub.Name)/$($_.Name)" })
            }
            $mine = @($here | Where-Object { $dist -notcontains $_ })
            $gone = @($dist | Where-Object { $here -notcontains $_ })
            $mod = @(Invoke-DxGit diff --name-only --diff-filter=M $script:Dx.Base '--' backend/tests | Where-Object { $_ })
            $levels = @($dist | ForEach-Object { Get-DxTestLevel $_ } | Select-Object -Unique)
            $perFile = @($levels | ForEach-Object { $lv = $_; "$(Get-DxTestLevelLabel $lv) $(@($dist | Where-Object { (Get-DxTestLevel $_) -eq $lv }).Count)" }) -join '・'
            "配布されたテスト   => $($dist.Count)ファイル（$perFile。これだけを実行する）"
            "自分で作ったテスト => $(if ($mine.Count -gt 0) { $mine -join ', ' } else { 'なし' })（実行しない）"
            "書き換えた既存テスト => $(if ($mod.Count -gt 0) { $mod -join ', ' } else { 'なし' })"
            if ($gone.Count -gt 0) { "消えた既存テスト   => $($gone -join ', ')" }
            ''
            $rel = @($dist | Where-Object { $here -contains $_ } | ForEach-Object { Join-Path $script:Dx.Repo ($_ -replace '/', '\') })
            if ($rel.Count -eq 0) { '実行できるテストが無い'; return }
            # キャッシュ（.pytest_cache）とバイトコード（__pycache__）を書かせない。作業ツリーを変えないため
            $prevB = $env:PYTHONDONTWRITEBYTECODE
            $env:PYTHONDONTWRITEBYTECODE = '1'
            # 配布されたテストの中に、.env の DATABASE_URL（sqlite:///./ecommerce.db）へテーブルを作るものがある。
            # 相対パスはカレントから解決されるので、backend で走らせると DB が無ければ新しく作られ、
            # あれば受講者の DB にテーブルが足される。EShop の外の空のフォルダをカレントにして走らせ、
            # 終わったら消す。.env は app の置き場から探されるので、読まれる値は backend で走らせたときと同じ。
            # 設定（pyproject.toml）もテストの置き場から探されるので、--rootdir で backend を指す
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "eshop-diagnose-$PID-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
            $null = New-Item -ItemType Directory -Path $tmp -Force
            Push-Location -LiteralPath $tmp
            try {
                # 置き場ごとの件数を数えるため、結果を一時フォルダの XML にも書かせる（-q では XML の場所を表示しない）
                $xml = Join-Path $tmp 'result.xml'
                & $py -m pytest -q -p no:cacheprovider --rootdir $script:Dx.Src --disable-warnings --tb=line -rfE --junitxml $xml @rel 2>&1 | ForEach-Object { "$_" }
                if (Test-Path -LiteralPath $xml) {
                    try {
                        [xml]$doc = Get-Content -LiteralPath $xml -Raw -Encoding UTF8
                        # classname は backend からのパスを . でつないだもの（tests.integration.test_cart.TestAddItem など）
                        $pass = [ordered]@{}
                        foreach ($lv in $levels) { $pass[$lv] = 0 }
                        foreach ($tc in @($doc.SelectNodes('//testcase'))) {
                            if ($tc.SelectSingleNode('failure|error|skipped')) { continue }
                            $lv = if ("$($tc.classname)" -match '^tests\.([^.]+)\.test_') { $Matches[1] } else { '' }
                            if (-not $pass.Contains($lv)) { $pass[$lv] = 0 }
                            $pass[$lv] += 1
                        }
                        ''
                        "PASS の内訳 => $(@($pass.Keys | ForEach-Object { "$(Get-DxTestLevelLabel $_) $($pass[$_])件" }) -join '・')"
                        $ex = $script:Dx.Expect
                        if (-not $ex.Error -and $script:Dx.Branch -eq $ex.Branch -and $ex.ExpectedByLevel.Count -gt 0) {
                            "基準の内訳 => $(@($ex.ExpectedByLevel.Keys | ForEach-Object { "$(Get-DxTestLevelLabel $_) $($ex.ExpectedByLevel[$_])件" }) -join '・')"
                        }
                    } catch {
                        'PASS の内訳 => 結果を読めない'
                    }
                }
            } finally {
                Pop-Location
                $env:PYTHONDONTWRITEBYTECODE = $prevB
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        } -Hint {
            param($text)
            if ($text -match '仮想環境が無い') { Write-Mark '未確認' '仮想環境が無い（D3-1）'; return '未確認' }
            if ($text -match '実行できるテストが無い') {
                Write-Mark 'NG' '配布されたテストのファイルが無い'
                Write-Fix '講師に申し出る'
                return 'NG'
            }
            $passed = if ($text -match '(\d+) passed') { [int]$Matches[1] } else { 0 }
            $failed = if ($text -match '(\d+) failed') { [int]$Matches[1] } else { 0 }
            $errors = if ($text -match '(\d+) errors?\b') { [int]$Matches[1] } else { 0 }
            if ($text -match "No module named '?(\w+)") {
                Write-Mark 'NG' "パッケージ（$($Matches[1])）が入っていないため、テストを読み込めない"
                Write-Fix '01-01 手順2: 仮想環境を有効にして、backend で pip install -r requirements.txt'
                return 'NG'
            }
            if ($passed + $failed -eq 0) {
                # 1件も走っていない。テストの失敗ではなく、conftest やアプリの読み込みで落ちている
                Write-Mark 'NG' 'テストを読み込めない（上の出力の最後の E の行が原因）'
                Write-Fix '先に D2-3（.env）と D3-3（依存パッケージ）を直す。どちらも OK なら、上の出力を講師に見せる'
                return 'NG'
            }
            if ($failed + $errors -gt 0) {
                Write-Mark 'NG' "配布されたテストが失敗している（PASS ${passed}件・失敗 ${failed}件・エラー ${errors}件）"
                # 段階ごとの直し方は期待値（testFailFix）にある。無ければ、どの段階にも当てはまる直し方
                $ex = $script:Dx.Expect
                $fix = if (-not $ex.Error -and $script:Dx.Branch -eq $ex.Branch) { @($ex.TestFailFix) } else { @() }
                if ($fix.Count -eq 0) { $fix = @('D2-3（.env）と D3-3（依存パッケージ）を先に見る。どちらも OK なら講師に申し出る') }
                foreach ($f in $fix) { Write-Fix $f }
                return 'NG'
            }
            # 基準の件数はブランチで違うので期待値から引く。手順書に無いブランチでは比べない
            $ex = $script:Dx.Expect
            if ($ex.Error) {
                Write-Mark '未確認' "${passed}件すべて PASS。基準の件数は、期待値を読めないため比べていない（$($ex.Error)）"
                return '未確認'
            }
            $expect = if ($script:Dx.Branch -eq $ex.Branch) { $ex.ExpectedTests } else { 0 }
            if ($expect -gt 0 -and $passed -ne $expect) {
                Write-Mark '注意' "すべて PASS だが、件数が基準（${expect}件）と違う（${passed}件）"
                if ($text -match '書き換えた既存テスト => (?!なし)' -or $text -match '消えた既存テスト') {
                    # 上の出力の「書き換えた既存テスト」「消えた既存テスト」の行から、戻すファイルを引く
                    $paths = @([regex]::Matches($text, '(?m)^(?:書き換えた既存テスト|消えた既存テスト)\s*=> (.+?)\s*$') |
                        ForEach-Object { $_.Groups[1].Value -split ',\s*' })
                    Write-Fix "03-03 手順2: 書き換えた・消した既存テストを backend で $(Get-DxRestoreFix $paths) で戻す"
                } else {
                    Write-Fix '講師に申し出る（ブランチの状態を一緒に確かめる）'
                }
                return '注意'
            }
            $split = if ($text -match '(?m)^PASS の内訳 => (.+?)\s*$') { "。$($Matches[1])" } else { '' }
            Write-Mark 'OK' "${passed}件すべて PASS$(if ($expect -gt 0) { '（基準どおり）' })$split"
            return 'OK'
        }
    }
}

# ---------------------------------------------------------------- 記録

function Save-DiagnoseRecord {
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine('# EShop 診断の記録')
    $null = $sb.AppendLine()
    $null = $sb.AppendLine("- 実施日時: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $null = $sb.AppendLine("- PC: $env:COMPUTERNAME")
    $null = $sb.AppendLine("- EShop: $($script:Dx.Repo)")
    $null = $sb.AppendLine("- ブランチ: $(if ($script:Dx.Branch) { $script:Dx.Branch } else { '（なし）' })（$($script:Dx.Stage)）")
    $null = $sb.AppendLine("- pytest: $(if ($SkipTest) { '実行していない（-SkipTest）' } else { '実行した' })")
    $null = $sb.AppendLine("- スクリプトの版: $script:ScriptVersion")
    $null = $sb.AppendLine("- PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))　文字コード: CP$($script:ConsoleCodePage)")
    $null = $sb.AppendLine('- 読み取りだけの診断で、EShop のファイルは変えていない。.env の値は記録していない')
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('## 判定一覧')
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('| 区分 | 項目 | 判定 | 手順書 |')
    $null = $sb.AppendLine('| :-- | :-- | :-- | :-- |')
    foreach ($r in $script:DxResults) {
        $null = $sb.AppendLine("| $($r.Group) | $($r.Id) $($r.Title) | $($r.Verdict) | $($r.Ref) |")
    }
    $todo = @($script:DxResults | Where-Object { $_.Verdict -in 'NG', '注意' })
    if ($todo.Count -gt 0) {
        $null = $sb.AppendLine()
        $null = $sb.AppendLine('## 直し方')
        foreach ($r in $todo) {
            $null = $sb.AppendLine()
            $null = $sb.AppendLine("- [$($r.Verdict)] $($r.Id) $($r.Title)（$($r.Ref)）")
            foreach ($f in $r.Fix) { $null = $sb.AppendLine("  - $f") }
        }
    }
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('## 各項目の出力')
    foreach ($r in $script:DxResults) {
        $null = $sb.AppendLine()
        $null = $sb.AppendLine("### $($r.Id) $($r.Title)  [$($r.Verdict)]")
        if ($r.Output) {
            $null = $sb.AppendLine()
            $null = $sb.AppendLine('```text')
            $null = $sb.AppendLine($r.Output.TrimEnd())
            $null = $sb.AppendLine('```')
        }
    }
    [System.IO.File]::WriteAllText($script:DxRecord, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))
}

# ---------------------------------------------------------------- 診断

function Invoke-Diagnose {
    # PowerShell 7.3 以降でこれが有効だと、git の終了コードが 0 以外のとき（diff --quiet の差あり、
    # rev-parse --verify の該当なし）にエラーが画面に出る。ここで切ると、呼び出す関数にも効く
    $PSNativeCommandUseErrorActionPreference = $false

    Write-Head ' EShop の診断（読み取りのみ。ファイルは変えない）'

    $repo = if ($EShopDir) { (Resolve-Path -LiteralPath $EShopDir -ErrorAction SilentlyContinue).Path } else { Find-EShopDir (Get-Location).Path }
    if (-not $repo -or -not (Test-Path (Join-Path $repo 'backend\app\main.py'))) {
        Write-Mark 'NG' 'EShop のフォルダが見つからない'
        Write-Host "        カレント: $((Get-Location).Path)" -ForegroundColor DarkGray
        Write-Host '        VS Code で EShop フォルダを開いたターミナルで実行するか、-EShopDir で場所を指定する' -ForegroundColor Yellow
        Write-Host '        まだ clone していないなら、01-01 手順1 からやり直す' -ForegroundColor Yellow
        return
    }
    $script:Dx = @{ Repo = $repo; Src = (Join-Path $repo 'backend') }
    $br = "$(@(Invoke-DxGit branch --show-current)[0])".Trim()
    if ($br -match '^(fatal|error):') { $br = '' }
    $script:Dx.Branch = $br
    # 期待するブランチ名と段階は tools\check-setup.json から読む。いまのブランチが期待と違えば段階は決めない
    $script:Dx.Expect = Read-DxExpect $repo
    $ex = $script:Dx.Expect
    $script:Dx.Stage = if ($ex.Error) { '期待値を読めないため判定できない' }
                       elseif ($br -and $br -eq $ex.Branch) { $ex.Stage }
                       else { "期待するブランチ（$($ex.Branch)）と違うため判定できない" }
    $null = @(Invoke-DxGit rev-parse --verify --quiet "origin/$br")
    $script:Dx.Base = if ($br -and $LASTEXITCODE -eq 0) { "origin/$br" } else { 'HEAD' }

    # 版は EShop が決まってから読む。起動方法3ではファイルの場所が分からないため、見つけた EShop の
    # tools\check-setup.ps1 で引く
    $script:ScriptVersion = Get-ScriptVersion $repo

    $out = if ($OutDir) { $OutDir } else { Split-Path $repo -Parent }
    $script:DxRecord = Join-Path $out "eshop-diagnose-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"

    $script:Checks = @()
    $script:DxResults = @()
    Set-CheckList

    Write-Host @"
  スクリプトの版 : $script:ScriptVersion
  EShop          : $repo
  ブランチ       : $(if ($br) { $br } else { '（なし）' })（$($script:Dx.Stage)）
  項目           : $($script:Checks.Count)件$(if ($SkipTest) { '（pytest は実行しない）' })
  記録           : $script:DxRecord
"@ -ForegroundColor Gray

    $n = $script:Checks.Count
    $i = 0
    foreach ($c in $script:Checks) {
        $i++
        Write-Host ''
        Write-Host (' [{0}/{1}] {2}  {3} {4}' -f $i, $n, $c.Group, $c.Id, $c.Title) -ForegroundColor Cyan -NoNewline
        Write-Host "  （$($c.Ref)）" -ForegroundColor DarkGray
        $script:DxFix = @()
        $r = Invoke-Check $c
        $v = if ($r.Suggest) { $r.Suggest } else { '参考' }
        $script:DxResults += [pscustomobject]@{
            Id = $c.Id; Group = $c.Group; Title = $c.Title; Ref = $c.Ref
            Verdict = $v; Output = $r.Text; Fix = @($script:DxFix)
        }
        # 1項目ごとに書き出す。途中で止めても、そこまでの結果は残る
        try { Save-DiagnoseRecord } catch { }
    }

    Write-Head ' 診断結果'
    foreach ($r in $script:DxResults) {
        Write-Host ('  {0}  {1,-6} {2} / {3}' -f (Get-MarkLabel $r.Verdict), $r.Id, $r.Group, $r.Title) -ForegroundColor (Get-MarkColor $r.Verdict)
    }
    $cnt = { param($v) @($script:DxResults | Where-Object Verdict -eq $v).Count }
    Write-Host ''
    Write-Host ("  OK {0} / NG {1} / 注意 {2} / 参考 {3} / 未確認 {4}" -f (& $cnt 'OK'), (& $cnt 'NG'), (& $cnt '注意'), (& $cnt '参考'), (& $cnt '未確認')) -ForegroundColor White

    $todo = @($script:DxResults | Where-Object { $_.Verdict -eq 'NG' }) + @($script:DxResults | Where-Object { $_.Verdict -eq '注意' })
    Write-Host ''
    if ($todo.Count -gt 0) {
        Write-Host '  直し方（NG から順に。前の項目が原因で後ろが NG になっていることがある）' -ForegroundColor Cyan
        foreach ($r in $todo) {
            Write-Host ("  [{0}] {1} {2}（{3}）" -f $r.Verdict, $r.Id, $r.Title, $r.Ref) -ForegroundColor (Get-MarkColor $r.Verdict)
            foreach ($f in $r.Fix) { Write-Host "        → $f" -ForegroundColor Yellow }
        }
    } else {
        Write-Host '  手順書どおりの状態。うまくいかない操作があれば、その画面を講師に見せる' -ForegroundColor Green
    }
    Write-Host ''
    if (Test-Path -LiteralPath $script:DxRecord) {
        Write-Host "  記録: $script:DxRecord" -ForegroundColor Green
        Write-Host '  講師に言われたときだけ、このファイルを共有フォルダにアップロードする' -ForegroundColor DarkGray
    } else {
        Write-Host "  記録を書き出せなかった: $script:DxRecord（-OutDir で別の場所を指定できる）" -ForegroundColor Yellow
    }
    Write-Host ''
}

# ---------------------------------------------------------------- 起点

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host 'PowerShell 5.1 以上で実行する' -ForegroundColor Red
    return
}

try {
    Invoke-Diagnose
} finally {
    # 起動方法3ではこのスクリプトがターミナルと同じプロセスで動くので、変えた環境変数を戻す
    $env:PYTHONIOENCODING = $script:PrevPythonIoEncoding
}
