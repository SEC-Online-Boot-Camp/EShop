<#
    事前確認書 第I部（実機確認）の対話型ランナー

    1ステップずつ「これから実行するコマンド」と結果を表示する。止まるのは人が操作・
    判断するところだけで、機械が判定できるステップは確認を求めずに流す。判定（OK / NG /
    保留）とメモをその場で入力すると、そのつど記録ファイルへ書き足される。

    自動で流したステップの判定がNGになったときは、その場で止まる。

    管理者権限は不要。機材の状態を変えるステップは <設定変更> と表示され、
    既定はスキップで、明示的にyを押したときだけ実行する。

    このファイルの正本は教材リポジトリ側にあり、ここへは配備されたものが置かれる。
    直すときは正本を直し、deploy-rehearsal.py で配備する。

    配備先は公開リポジトリで、受講者からも参照できる（普通の git clone でも
    リモート追跡ブランチとして付いてくる）。受講者に伏せる情報はここに書かない。

    リハーサル機での取得（作業ツリーに main / coupon は展開されない）

        git clone -b rehearsal --single-branch https://github.com/SEC-Online-Boot-Camp/EShop.git EShop-rehearsal
        cd EShop-rehearsal

    起動方法（上から順に試す）

        1) 通常
           .\precheck.ps1

        2) 「このシステムではスクリプトの実行が無効になっている」と出る場合
           powershell -ExecutionPolicy Bypass -File .\precheck.ps1

        3) 2でも同じエラーになる場合（グループポリシーで縛られているPC）
           & ([scriptblock]::Create((Get-Content .\precheck.ps1 -Raw)))

           実行ポリシーが禁じているのはスクリプトファイル（.ps1）の実行だけなので、
           中身を文字列として読み込んで実行するこの形は管理者権限なしで通る。
           引数を渡す場合は末尾に足す:
           & ([scriptblock]::Create((Get-Content .\precheck.ps1 -Raw))) -DryRun

    出力されるファイル

        既定の置き場は C:\rehearsal-<日付>（作れない機材では利用者フォルダ直下）。
        作業フォルダ（EShopのclone先）も同じところになるので、終わったらフォルダごと
        消せば片付く。デスクトップを使わないのは、OneDriveへ同期されると6章の所要時間
        の実測が当てにならなくなるため。-WorkDir / -OutDir で変えられる。

        precheck-result-<日時>.md   判定・所要時間・各ステップの出力とメモ
                                    1ステップごとに書き足すので、中断しても残る
        precheck-steps-<日時>.md    -DryRun で出るステップ一覧
        rehearsal-check.txt         Start-Transcript の記録（画面に出たものすべて）

    引数

        -DryRun          何も実行せず、全ステップの内容だけを順に表示する（下見用）
        -Auto            止まらずに最後まで走らせる。判定の根拠があるステップは自動で判定し、
                         無いものは「自動」として記録する。人が操作するステップ
                         （手動操作・聞き取り）は「未実施」として記録し、飛ばす
        -AllowChanges    -Auto のときに、機材の状態を変えるステップも実行する
                         （既定では実行しない）
        -Chapter 2,3     指定した章だけを実施する。章を指定しないときは、社内で確定させる
                         5章の挙動確認（5-2〜5-9）を除いた2〜7章を実施する。5章は
                         -Chapter 5 で明示したときだけ対象になる
        -WorkDir <path>  EShopをcloneする作業フォルダ（既定 C:\rehearsal-<日付>）
        -MaterialDir <p> docs-template があるフォルダ（4-4-01で使う。既定はこのスクリプトの場所）
        -OutDir <path>   記録の出力先（既定は作業フォルダと同じ）
        -NoTranscript    Start-Transcriptを使わない

    講座当日の診断（受講者のPCで、受講者が実行する）

        -Diagnose        受講者の EShop の状態を読み取りだけで診断する。リハーサルのステップは
                         実行せず、clone・pip・seed・DBの削除・ブランチの切り替えも行わない。
                         NGや注意のときは、手順書のどの手順をやり直すかを表示する
        -Network         -Diagnose と一緒に指定したときだけ、プロキシ設定の方式と外部ホストへの
                         到達性（3章と同じ確認）も行う。通信が疑わしいときに講師が指示する
        -EShopDir <p>    診断する EShop のフォルダ（既定はカレントから上へたどって見つける）
        -SkipTest        -Diagnose で pytest を実行しない
        -OutDir <path>   -Diagnose の記録の出力先（既定は EShop の親フォルダ）

        受講者のPCでの取得と起動（EShop の中ならどのフォルダからでもよい）

            git fetch origin rehearsal
            git -C (git rev-parse --show-toplevel) archive -o "$env:TEMP\eshop-diagnose.zip" origin/rehearsal precheck.ps1
            Expand-Archive "$env:TEMP\eshop-diagnose.zip" "$env:TEMP\eshop-diagnose" -Force
            & "$env:TEMP\eshop-diagnose\precheck.ps1" -Diagnose

        最後の行が実行ポリシーで弾かれる場合は、起動方法3と同じ形にする:
            & ([scriptblock]::Create((Get-Content "$env:TEMP\eshop-diagnose\precheck.ps1" -Raw))) -Diagnose
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Auto,
    [switch]$AllowChanges,
    [string[]]$Chapter,
    [string]$WorkDir,
    [string]$MaterialDir,
    [string]$OutDir,
    [switch]$NoTranscript,
    [switch]$Diagnose,
    [switch]$Network,
    [string]$EShopDir,
    [switch]$SkipTest
)

$ErrorActionPreference = 'Continue'

# 正本は resource の 4-短期講座/AI活用入門講座/SW編/rehearsal にある。
# 次の1行は deploy-rehearsal.py が配備時に書き換える（触らない）。
$script:ScriptVersion = 'dev（未配備。正本を直接実行している）'

# PowerShellがネイティブコマンドの出力を解釈する文字コードに、Python側の出力を合わせる。
# Pythonはパイプ出力のときロケールの文字コード（日本語WindowsならCP932）で書くため、
# 揃えないと記録が文字化けし、seedの件数の自動判定も誤る。
# [Console]::OutputEncoding は機材によって変わる（プロファイルでUTF-8にしてある機材は
# 65001、素のWindowsは932）。版では決まらないので、実際の値を読んで合わせる。
# 65001（PowerShell 7.6.6）と 932（PowerShell 5.1）の両方で文字化け0を確認済み。
$script:ConsoleCodePage = [Console]::OutputEncoding.CodePage
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

function Write-Label([string]$label, [string]$value, [string]$color = 'Gray') {
    if (-not $value) { return }
    foreach ($line in ($value -split "`n")) {
        Write-Host ('  {0,-8}' -f $label) -NoNewline -ForegroundColor DarkGray
        Write-Host $line -ForegroundColor $color
        $label = ''
    }
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
        '保留' { 'Yellow' }
        '注意' { 'Yellow' }      # -Diagnose で使う。動くが手順書どおりでない
        '参考' { 'Gray' }
        '未実施' { 'Yellow' }    # 人の操作が要る。まとめの強調ブロックと色を揃える
        default { 'DarkGray' }   # 自動・スキップ・記録・確認
    }
}

function Write-Mark([string]$Mark, [string]$Text) {
    # 判定を行頭に出す。色が落ちる記録（rehearsal-check.txt）でも、読み飛ばしてよい行と
    # ここで止まる行が見分けられるようにするため。幅を揃えて後続の説明行とぶら下げを合わせる。
    Write-Host ('  {0}  {1}' -f (Get-MarkLabel $Mark), $Text) -ForegroundColor (Get-MarkColor $Mark)
}

function Remove-AnsiEscape([string]$Text) {
    # pytest などが色付けに使う制御シーケンスを外す。残すとmdが読めなくなる
    if (-not $Text) { return $Text }
    $esc = [char]27
    return ($Text -replace "$esc\[[0-9;?]*[ -/]*[@-~]", '' -replace "$esc\][^$esc]*($([char]7)|$esc\\)", '')
}

# 講座で使う公開ホスト。社内の除外リスト（NO_PROXY・ProxyOverride）に載っていることが
# あるが、これを伏せると「どのホストが落ちたのか」が記録から読めなくなり、10章の申請に
# 上げる材料が消える。公開情報なので伏せる必要もない。
$script:RedactionAllow = @(
    'claude.ai', 'claude.com', 'platform.claude.com', 'api.anthropic.com', 'downloads.claude.ai',
    'anthropic.com', 'github.com', 'githubusercontent.com', 'pypi.org', 'pythonhosted.org',
    'files.pythonhosted.org', 'marketplace.visualstudio.com', 'visualstudio.com', 'vsassets.io',
    'microsoft.com', 'python.org'
)

function Test-RedactionAllowed([string]$Text) {
    $t = $Text.Trim().TrimStart('.', '*').TrimEnd('.')
    foreach ($a in $script:RedactionAllow) {
        if ($t -eq $a -or $t.EndsWith(".$a")) { return $true }
    }
    return $false
}

function Add-RedactionToken([string]$Text, [string]$Label) {
    if (-not $Text) { return }
    $t = $Text.Trim()
    if (-not $t) { return }
    if ($t.Length -lt 5) { return }
    if ($t -match '^(localhost|127\.0\.0\.1|::1|<local>|\*)$') { return }
    if (Test-RedactionAllowed $t) { return }
    if ($script:Redactions | Where-Object { $_.Text -eq $t }) { return }
    $script:Redactions += [pscustomobject]@{ Text = $t; Label = $Label }
    # ProxyOverride は「*.社内ドメイン」の形で書かれるが、出力に出るのは * の付かない形
    if ($t.StartsWith('*.')) { Add-RedactionToken $t.Substring(1) $Label }
}

function Add-Redaction([string]$Value, [string]$Label) {
    if (-not $Value) { return }
    foreach ($tok in ($Value -split '[,;]')) {
        $t = $tok.Trim()
        if (-not $t) { continue }
        Add-RedactionToken $t $Label
        # 環境変数には http://proxy.example.local:8080 の形で入るが、pip や git が失敗した
        # ときの文面には proxy.example.local:8080 や proxy.example.local の形で出る。
        # 完全一致だけだと素通りするため、ホスト名だけでも伏せられるように登録する。
        $candidate = if ($t -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $t } else { "http://$t" }
        $u = try { [Uri]$candidate } catch { $null }
        if ($u -and $u.Host) {
            Add-RedactionToken $u.Authority $Label
            Add-RedactionToken $u.Host $Label
        }
    }
}

function Hide-NetworkInfo([string]$Text) {
    # 記録に残す文字列から、客先のネットワーク情報を伏せる。
    # pip や git が失敗したときの文面にプロキシのアドレスが混ざることがあるため、
    # 画面には出したまま、ファイルへ書く分だけ置き換える。
    if (-not $Text) { return $Text }
    foreach ($r in ($script:Redactions | Sort-Object { $_.Text.Length } -Descending)) {
        $pat = [regex]::Escape($r.Text)
        # NO_PROXY は「.社内ドメイン」の形で書かれる。手前のラベルを残すと社内のホスト名が
        # 部分的に漏れる（<ホスト名>.社内ドメイン → <ホスト名>だけ残る）ので、ラベルごと置き換える。
        # ドットを含め 0文字以上にしてあるのは、多段のサブドメイン（a.b.社内ドメイン）と、
        # 手前にラベルが無い裸のサフィックス（除外リストの表記そのもの）の両方を拾うため。
        if ($r.Text.StartsWith('.')) { $pat = '[A-Za-z0-9_.-]*' + $pat }
        $Text = $Text -replace $pat, $r.Label
    }
    # IPアドレス（CIDR・ポート付きも）。127.0.0.1 は残す
    $Text = $Text -replace '(?<!\d)(?!127\.0\.0\.1(?!\d))\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(/\d{1,2})?(:\d+)?', '<アドレス>'
    # 172.20.* のようなワイルドカード表記
    $Text = $Text -replace '(?<!\d)\d{1,3}\.\d{1,3}(\.\d{1,3})?\.\*', '<アドレス>'
    return $Text
}

# 別のターミナルで python 系を動かすときの整え方。実行ポリシーが Restricted の機材では
# .venv\Scripts\activate（Activate.ps1）が弾かれるので、venv の exe を直接呼ぶ形を先に出す。
# このスクリプト自身は venv の python を絶対パスで呼ぶため activate を必要としない。
$script:VenvNote = @'
  実行ポリシーが Restricted の機材では activate（Activate.ps1）が弾かれるため、
  backend へ移動して .venv\Scripts\ の実行ファイルを直接呼ぶ形が確実。
  (.venv) の表示が要るときだけ、01-01手順書の代替1行を手打ちする（4-3-07 参照）。
'@

# 3-4-1（環境変数の経路 / curl）と 3-4-2（システム設定の経路 / Invoke-WebRequest）は
# 同じホストを見る。3-6-a が両者の「落ち」件数を比べてケースを決めるため、片方にだけ
# 足すと、そのホストが許可リストに無いだけで「環境変数の経路が通らない」と誤判定する。
# 増やすときは必ずここだけを直す。
$script:ReachHosts = @(
    'https://claude.ai'
    'https://claude.com'
    'https://platform.claude.com'
    'https://api.anthropic.com'
    'https://downloads.claude.ai'
    'https://github.com'
    'https://pypi.org/simple/'
    'https://files.pythonhosted.org'
    'https://marketplace.visualstudio.com'
    # 拡張のCDNは発行者名のサブドメイン（anthropic.claude-code の anthropic）。
    # marketplaceだけ通ってCDNが落ちると「一覧は見えるのに導入で失敗する」になる。
    'https://anthropic.gallerycdn.vsassets.io/'
)

function Get-Reachability([string]$Text) {
    # 3-4-1 / 3-4-2 の出力から、到達できた数と落ちた数を数える
    $ok = 0; $bad = 0; $auth = $false
    foreach ($line in ($Text -split "`n")) {
        if ($line -match '^\s*(https\S+)\s+(.+?)\s*$') {
            $v = $Matches[2].Trim()
            # 数字だけの行（curl）と、例外メッセージ中の (403) 等（Invoke-WebRequest）の両方を拾う。
            # 3-3のとおり 403 や 404 は「到達成功」なので、文面で返ってきても落ちと数えない。
            $code = $null
            if ($v -match '^\d+$') { $code = $v }
            elseif ($v -match '\((\d{3})\)') { $code = $Matches[1] }
            if ($code) {
                if ($code -eq '407') { $auth = $true; $bad++ }
                elseif ($code -match '^(200|301|302|401|403|404)$') { $ok++ }
                else { $bad++ }
            } else {
                $bad++
                if ($v -match '407') { $auth = $true }
            }
        }
    }
    return @{ OK = $ok; Bad = $bad; Auth = $auth }
}

function Read-Key([string]$prompt) {
    Write-Host ''
    Write-Host $prompt -ForegroundColor Yellow
    Write-Host '  > ' -NoNewline -ForegroundColor Yellow
    return (Read-Host).Trim()
}

# ---------------------------------------------------------------- 状態

$script:Steps    = @()
$script:Results  = @()
$script:Timings  = @{}
$script:Captured = @{}
$script:Aborted  = $false

function New-Step {
    param(
        [string]$Id,
        [string]$Ch,
        [string]$Title,
        [ValidateSet('auto', 'change', 'manual', 'ask', 'info')]
        [string]$Kind = 'auto',
        [string]$Purpose,
        [string]$Expect,
        [string]$Show,
        [scriptblock]$Cmd,
        [scriptblock]$Hint,
        [string]$SkipImpact,
        [string]$Ask,
        [string]$TimeKey,
        [switch]$NeedsInput,
        [ValidateSet('', 'materials')]
        [string]$Site = ''
    )
    $script:Steps += [pscustomobject]@{
        Id = $Id; Ch = $Ch; Title = $Title; Kind = $Kind
        Purpose = $Purpose; Expect = $Expect; Show = $Show
        Cmd = $Cmd; Hint = $Hint; SkipImpact = $SkipImpact; Ask = $Ask; TimeKey = $TimeKey
        NeedsInput = [bool]$NeedsInput; Site = $Site
    }
}

function Add-Result {
    param($Step, [string]$Verdict, [string]$Output, [string]$Memo, [double]$Seconds = -1)
    # 人が打ち込んだ観測結果（manualステップ）とメモは Invoke-Step を通らないので、
    # ここで伏せ字を当てる。ログイン失敗の文面にはプロキシのホスト名やPACのURLが出る。
    # コマンド出力は Invoke-Step で当て済みだが、置き換えたあとの <プロキシ> 等は
    # 伏せ字の対象にならないため、二重に通しても変わらない。
    $Output = Hide-NetworkInfo $Output
    $Memo = Hide-NetworkInfo $Memo
    $script:Results += [pscustomobject]@{
        Id = $Step.Id; Ch = $Step.Ch; Title = $Step.Title; Kind = $Step.Kind
        Command = (Get-ShowText $Step)
        Verdict = $Verdict; Output = $Output; Memo = $Memo
        Seconds = $Seconds; At = (Get-Date).ToString('HH:mm:ss')
    }
    # 1ステップごとに書き出す。中断しても、そこまでの結果はファイルに残る
    try { Save-Record | Out-Null }
    catch { Write-Host "  記録の書き出しに失敗した（続行する）: $($_.Exception.Message)" -ForegroundColor Yellow }
}

function Get-ShowText($Step) {
    if ($Step.Show) { return $Step.Show }
    if ($Step.Cmd) {
        $t = $Step.Cmd.ToString().Trim() -split "`n" | ForEach-Object { $_.Trim().TrimEnd('`') }
        return ($t -join "`n")
    }
    return ''
}

# ---------------------------------------------------------------- パス

function Get-VenvPython {
    $p = Join-Path $script:SrcDir '.venv\Scripts\python.exe'
    if (Test-Path $p) { return $p }
    # ここで 'python' に落とすと、貸与機のグローバルなPythonに pip install が走る。
    # 7章の原状復帰はcloneしたフォルダと環境変数しか戻さないので、それは回収できない。
    throw "仮想環境が無い: $p（4-3-06 のvenv作成が失敗している。ここから先は実行しない）"
}

function Invoke-InSrc([scriptblock]$Block) {
    if (-not (Test-Path $script:SrcDir)) {
        Write-Host "  作業フォルダがまだ無い: $($script:SrcDir)" -ForegroundColor Red
        return
    }
    Push-Location $script:SrcDir
    try { & $Block } finally { Pop-Location }
}

function Invoke-InRepo([scriptblock]$Block) {
    if (-not (Test-Path $script:RepoDir)) {
        Write-Host "  リポジトリがまだ無い: $($script:RepoDir)" -ForegroundColor Red
        return
    }
    Push-Location $script:RepoDir
    try { & $Block } finally { Pop-Location }
}

# ---------------------------------------------------------------- ステップ定義

function Set-StepList {

    # ====================== 2章 受講PCの基本構成 ======================

    New-Step -Id '2-1-a' -Ch '2' -Title 'Windowsの版' -Kind auto `
        -Purpose '受講PCのOSと版を記録する（本番機と同じかを後で照合する）' `
        -Expect '版とビルドを記録する' `
        -Show 'レジストリのCurrentVersionから版・ビルド・UBRを読む（buildで世代も判定する）' `
        -Cmd {
            $v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' |
                Select-Object ProductName, DisplayVersion, CurrentBuild, UBR
            $v
            # ProductName は Windows 11 でも「Windows 10 Pro」と返る。記録を後から読む人が
            # 誤読するため、build から判定した結果を書いておく（22000以上が Windows 11）。
            $b = 0
            [void][int]::TryParse("$($v.CurrentBuild)", [ref]$b)
            "世代: $(if ($b -ge 22000) { 'Windows 11' } else { 'Windows 10' })（build $b で判定。ProductNameは11でも10と返る）"
        }

    New-Step -Id '2-1-c' -Ch '2' -Title 'PowerShellの実行ポリシー' -Kind auto `
        -Purpose '.venv\Scripts\activate が通るかを左右する' `
        -Expect 'MachinePolicy / UserPolicy が Undefined 以外なら、グループポリシーで縛られている' `
        -Show 'Get-ExecutionPolicy -List
（このコマンド自体が制限で動かない環境では、同じ値をレジストリから読む）' `
        -Cmd {
            $viaCmdlet = $false
            try {
                Get-ExecutionPolicy -List -ErrorAction Stop | Out-String -Width 120
                $viaCmdlet = $true
            } catch {
                "Get-ExecutionPolicy が使えなかった: $($_.Exception.Message)"
            }
            if (-not $viaCmdlet) {
                'レジストリから読む（同じ値が入っている）'
                $map = [ordered]@{
                    'MachinePolicy' = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell'
                    'UserPolicy'    = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\PowerShell'
                    'LocalMachine'  = 'HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'
                    'CurrentUser'   = 'HKCU:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'
                }
                foreach ($k in $map.Keys) {
                    $v = (Get-ItemProperty -Path $map[$k] -Name ExecutionPolicy -ErrorAction SilentlyContinue).ExecutionPolicy
                    "{0,-15} {1}" -f $k, $(if ($v) { $v } else { 'Undefined' })
                }
            }
        } `
        -Hint {
            param($text)
            if ($text -match '(?m)^\s*(MachinePolicy|UserPolicy)\s+(?!Undefined)\S+') {
                Write-Mark '参考' 'グループポリシーで縛られている。Set-ExecutionPolicy -Scope CurrentUser は効かないため、'
                Write-Host '        01-01手順書は代替1行だけに絞る（11章へ記録）' -ForegroundColor DarkGray
            } else {
                Write-Mark '参考' 'ポリシーによる縛りは無い。activateの可否は 4-3 の手順8で確定する'
            }
        }

    New-Step -Id '2-1-d' -Ch '2' -Title '空きディスク容量' -Kind auto `
        -Purpose 'Python環境・Claude Code・リポジトリで2GB以上使う' `
        -Expect '空きが2GB以上あること' `
        -Show 'Get-PSDrive C | Select-Object Used, Free' `
        -Cmd {
            Get-PSDrive C | Select-Object `
                @{n = 'Used(GB)'; e = { [math]::Round($_.Used / 1GB, 1) } },
                @{n = 'Free(GB)'; e = { [math]::Round($_.Free / 1GB, 1) } }
        } `
        -Hint {
            param($text)
            if ($text -match 'Free\(GB\)[\s\S]*?([\d\.]+)\s*$') {
                $free = [double]$Matches[1]
                if ($free -lt 2) { Write-Mark 'NG' "空きが2GBを下回っている（$free GB）"; return 'NG' }
                else { Write-Mark 'OK' "空きは足りている（$free GB）"; return 'OK' }
            }
        }

    New-Step -Id '2-2-a' -Ch '2' -Title 'VS Codeの版' -Kind auto `
        -Purpose '「PATHに追加」を選ばずに入れてあるとcodeが解決できない。導入の有無と区別する' `
        -Expect '導入済みであること' `
        -Show 'code --version（解決できない場合は実体の有無も見る）' `
        -Cmd {
            $v = try { code --version 2>&1 } catch { $null }
            if ($v) { $v } else { 'codeコマンドを解決できない' }
            foreach ($p in (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'),
                'C:\Program Files\Microsoft VS Code\Code.exe') {
                if (Test-Path $p) { "実体あり: $p"; break }
            }
        } `
        -Hint {
            param($text)
            if ($text -match '(?m)^\s*\d+\.\d+') { Write-Mark 'OK' '版を取得できた'; return 'OK' }
            if ($text -match '実体あり:') {
                Write-Mark '保留' '導入されているがcodeがPATHに無い。受講者にも同じ現象が出る'
                Write-Host '        講座ではcodeコマンドを使わないため実害は無いが、手順書の補足に載せる' -ForegroundColor Yellow
                return '保留'
            }
            Write-Mark 'NG' 'VS Codeが見つからない'
            return 'NG'
        }

    New-Step -Id '2-2-b' -Ch '2' -Title 'Pythonの版と実体パス' -Kind auto `
        -Purpose '依存パッケージが完全固定のため、版によってwheelが無くビルドに失敗する（4-2）' `
        -Expect '3.11以上。WindowsApps配下のエイリアスでないこと' `
        -Cmd {
            python --version
            (Get-Command python -ErrorAction SilentlyContinue).Source
        } `
        -Hint {
            param($text)
            $ng = $false
            if ($text -match 'Python\s+3\.(\d+)') {
                $minor = [int]$Matches[1]
                if ($minor -lt 11) { Write-Mark 'NG' "3.11未満（3.$minor）。要件を満たさない"; $ng = $true }
                else { Write-Mark 'OK' "3.${minor}で要件を満たす" }
            } else { $ng = $true }
            # 版が返っていれば実体は入っている。WindowsApps 配下は Store版の置き場でもあり、
            # 3.14.7 で venv・完全固定のpip・seed・pytest まで通った実測がある（2026-09-18）。
            # 版を返さない場合だけが App Execution Alias のスタブ。
            if ($text -match 'WindowsApps') {
                if ($ng) {
                    Write-Mark 'NG' 'Microsoft Storeのエイリアス（スタブ）。実体のPythonが入っていない'
                } else {
                    Write-Mark '保留' 'Store版のPython。動くが、自動更新で版が変わる。受講PCと版が揃うかを8章で確認する'
                    return '保留'
                }
            }
            if ($ng) { return 'NG' } else { return 'OK' }
        }

    New-Step -Id '2-2-c' -Ch '2' -Title 'Gitの版' -Kind auto `
        -Purpose '4-3-05 のcloneに必要。無ければ受講者にも手動導入が要る' `
        -Expect '導入済みであること' `
        -Cmd { git --version } `
        -Hint {
            param($text)
            if ($text -match 'git version') { Write-Mark 'OK' '導入されている'; return 'OK' }
            Write-Mark 'NG' 'gitが見つからない。4章は実施できない'
            return 'NG'
        }

    New-Step -Id '2-2-d' -Ch '2' -Title 'PowerShellの版' -Kind auto `
        -Purpose '5.1と7ではプロキシの読み先が違う（3-1）' `
        -Expect 'このスクリプトを起動したシェルの版。受講者はVS Codeの統合ターミナルで操作するため、そこから起動する' `
        -Cmd { $PSVersionTable.PSVersion; "PSEdition = $($PSVersionTable.PSEdition)" }

    New-Step -Id '2-2-e' -Ch '2' -Title 'Excelの有無' -Kind auto `
        -Purpose '01-05-セキュリティチェックシート.xlsx の編集に必要' `
        -Expect 'Excelが導入されていること' `
        -Show 'App Paths（HKLM・HKCU）・.xlsxの関連付け・Click-to-Runの導入先を順に見る' `
        -Cmd {
            # 貸与機ではHKLMのApp Pathsも assoc も空だったのに、手で開いたら編集できた
            # （2026-09-18）。assoc は HKCR しか見ないので、利用者ごとの導入と
            # 利用者ごとの関連付けを拾えない。見る場所を増やす。
            foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\EXCEL.EXE',
                'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\EXCEL.EXE') {
                $v = (Get-ItemProperty $k -ErrorAction SilentlyContinue).'(default)'
                "App Paths {0,-4}: {1}" -f $(if ($k.StartsWith('HKLM')) { 'HKLM' } else { 'HKCU' }), $(if ($v) { $v } else { '見つからない' })
            }
            $uc = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.xlsx\UserChoice' -ErrorAction SilentlyContinue).ProgId
            "利用者ごとの関連付け: $(if ($uc) { $uc } else { '無し' })"
            $assoc = try { (cmd /c assoc .xlsx 2>&1) } catch { '' }
            "関連付け(.xlsx): $assoc"
            $c2r = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue).InstallationPath
            if ($c2r) { "Click-to-Run : $c2r" }
            $hit = $null
            foreach ($d in $c2r, 'C:\Program Files\Microsoft Office', 'C:\Program Files (x86)\Microsoft Office') {
                if (-not $d -or $hit) { continue }
                foreach ($sub in 'root\Office16', 'Office16') {
                    $p = Join-Path $d "$sub\EXCEL.EXE"
                    if (-not $hit -and (Test-Path $p)) { $hit = $p }
                }
            }
            if ($hit) { "実体あり: $hit" } else { '実体: よくある置き場には見つからない' }
        } `
        -Hint {
            param($text)
            if ($text -match 'EXCEL\.EXE') { Write-Mark 'OK' 'Excelが導入されている'; return 'OK' }
            if ($text -match 'Excel\.Sheet') { Write-Mark 'OK' '.xlsxがExcelに関連付けられている'; return 'OK' }
            # 自動では全ての導入形（Storeアプリ版・利用者ごとの導入）を網羅できない。
            # 実際に編集できた機材でNGを出した実績があるので、断定しない。
            Write-Mark '保留' '自動では見つけられなかった。xlsxを実際に開いて編集できるかを手で確かめる'
            Write-Host '        Storeアプリ版や利用者ごとの導入は、ここで見ている場所に出ないことがある' -ForegroundColor Yellow
            return '保留'
        }

    # ====================== 3章 ネットワークとプロキシ ======================

    New-Step -Id '3-2-1' -Ch '3' -Title 'プロキシ設定の有無' -Kind auto `
        -Purpose 'curl・pip・Claude Codeは環境変数だけを見る。設定されているかをまず見る' `
        -Expect '有無が3スコープで記録される' `
        -Show @"
  HTTP_PROXY / HTTPS_PROXY / NO_PROXY が設定されているかを、
  User・Machine・いま動いているプロセスの3スコープで確認する。

  **値は表示しない**（有無だけを見る）。アドレスが必要な場合は3-2-4を参照。
"@ `
        -Cmd {
            foreach ($n in 'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY') {
                $u = [Environment]::GetEnvironmentVariable($n, 'User')
                $m = [Environment]::GetEnvironmentVariable($n, 'Machine')
                $p = [Environment]::GetEnvironmentVariable($n)
                $f = { param($v) if ($v) { '設定あり' } else { 'なし    ' } }
                "{0,-12} User={1}  Machine={2}  プロセス={3}" -f $n, (& $f $u), (& $f $m), (& $f $p)
            }
        } `
        -Hint {
            param($text)
            if ($text -match 'プロセス=設定あり') {
                Write-Mark '参考' '設定されている。curl・pip・gitはプロキシを使う状態'
            } else {
                Write-Mark '参考' '設定されていない。3-4-1が通らなければ、手順書に設定を載せる（11章）'
            }
        }

    New-Step -Id '3-2-2' -Ch '3' -Title 'プロキシ設定の方式' -Kind auto `
        -Purpose 'ブラウザとVS Codeが見る設定。方式によって受講者への案内が変わる' `
        -Expect '固定アドレス指定 / PAC / WPAD自動検出 / なし のいずれかを判別できる' `
        -Show @"
  レジストリ（WinINET）と netsh winhttp から、**方式だけ**を読む。
  アドレス・PACのURL・除外リストは表示しない（3-2-4を参照）。
"@ `
        -Cmd {
            $k = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
            $has = { param($v) if ($v) { 'あり' } else { 'なし' } }
            "ProxyEnable   : $($k.ProxyEnable)"
            "ProxyServer   : $(& $has $k.ProxyServer)　（固定アドレスの明示設定）"
            "AutoConfigURL : $(& $has $k.AutoConfigURL)　（PAC方式）"
            "AutoDetect    : $(& $has $k.AutoDetect)　（WPAD自動検出）"
            $ovr = $k.ProxyOverride
            "ProxyOverride : $(& $has $ovr)　ローカル除外(<local>)の指定: $(if ($ovr -match '<local>') { 'あり' } else { 'なし' })"
            $nsh = (netsh winhttp show proxy 2>&1 | Out-String)
            if ($nsh -match 'Direct access|直接アクセス') { 'WinHTTP       : 直結（プロキシなし、または透過型）' }
            elseif ($nsh -match 'Proxy Server') { 'WinHTTP       : プロキシの指定あり' }
            else { 'WinHTTP       : 判別できない' }
            ''
            $way = @()
            if ($k.ProxyEnable -eq 1 -and $k.ProxyServer) { $way += '固定アドレス指定' }
            if ($k.AutoConfigURL) { $way += 'PAC' }
            if ($k.AutoDetect) { $way += 'WPAD自動検出' }
            if ($way.Count -eq 0) { '方式: 明示的な設定なし（透過型の可能性）' } else { "方式: $($way -join ' + ')" }
        } `
        -Hint {
            param($text)
            if ($text -match 'PAC') { Write-Mark '参考' 'PAC方式。宛先ごとの振り分けは3-2-3で見る' }
            if ($text -match 'ローカル除外\(<local>\)の指定: あり') { Write-Mark '参考' 'ローカルアドレスは迂回される（Swagger UIの表示に必要）' }
        }

    New-Step -Id '3-2-3' -Ch '3' -Title '宛先ごとの経路（プロキシ経由か直結か）' -Kind auto `
        -Purpose 'PAC方式でも宛先ごとの振り分けを判別できる。ローカルの迂回もここで見える' `
        -Expect '講座で使うホストが「プロキシ経由」か「直結」か。127.0.0.1は直結であること' `
        -Show @"
  システムのプロキシ設定に、宛先ごとの経路を問い合わせる。
  **プロキシのアドレスは表示しない**（経路の種別と迂回の有無だけ）。
"@ `
        -Cmd {
            $p = [System.Net.WebRequest]::GetSystemWebProxy()
            'https://claude.ai', 'https://api.anthropic.com', 'https://downloads.claude.ai', 'https://github.com', 'https://pypi.org', 'https://files.pythonhosted.org', 'https://marketplace.visualstudio.com', 'http://127.0.0.1:8000/docs' |
                ForEach-Object {
                    $u = [Uri]$_
                    $via = $p.GetProxy($u)
                    $bypass = $p.IsBypassed($u)
                    $route = if ($bypass -or $via.AbsoluteUri -eq $u.AbsoluteUri) { '直結' } else { 'プロキシ経由' }
                    "{0,-45} {1}  bypass={2}" -f $_, $route, $bypass
                }
        } `
        -Hint {
            param($text)
            foreach ($line in ($text -split "`n")) {
                if ($line -match '127\.0\.0\.1' -and $line -match 'プロキシ経由') {
                    Write-Mark 'NG' '127.0.0.1がプロキシに投げられる。Swagger UIの確認で詰まる（3-5-b 参照）'
                    return 'NG'
                }
            }
            Write-Mark 'OK' '127.0.0.1は直結。宛先ごとの振り分けを記録した'
            return 'OK'
        }

    New-Step -Id '3-2-4' -Ch '3' -Title 'アドレスや設定値が必要なとき（先方に確認していただく）' -Kind info `
        -Purpose '手順書に載せる実アドレスは講師が受け取らない。先方に記入していただく' `
        -Show @"
  プロキシのアドレス・PACの中身・除外リストは、**この場では扱わない**。
  客先のネットワーク情報であり、記録にも画面共有にも出さないためである。

  実値が必要になるのは、3-6-aの判定がケースB/Cのときだけ（受講者向け手順書に
  載せるアドレス）。その場合も講師は値を受け取らない。手順書にはプレースホルダ
  （<プロキシのアドレス:ポート> など）を書き、実値の記入は先方にお願いする。

  このステップではコマンドを実行しない。確認に使うコマンドが必要になったときは、
  講師から別途お渡しする。
"@

    New-Step -Id '3-3' -Ch '3' -Title '判定基準の確認（読むだけ）' -Kind info `
        -Purpose 'ここを誤読すると「通っているのに遮断」と判定してしまう' `
        -Show @"
  200 / 301 / 302 / 401 / 403 / 404        到達成功（TLSとHTTP応答が成立している）
  タイムアウト・接続拒否                   遮断（プロキシ未設定かファイアウォール）
  407 Proxy Authentication Required        認証付きプロキシ → 3-6のケースD
  証明書エラー（SSL certificate problem）  TLS傍受 → 4-3-08 の pip install で判定する
  プロキシが返す502/503・ブロック画面      許可リストに無い → IT部門へ申請
"@

    New-Step -Id '3-4-1' -Ch '3' -Title '到達性の確認（環境変数の経路 / curl.exe）' -Kind auto `
        -Purpose 'pip・git・Claude Codeと同じ経路で確かめる' `
        -Expect '各ホストのHTTPステータス。3-3の表で判定する' `
        -Cmd {
            $script:ReachHosts |
                ForEach-Object { "{0,-45} {1}" -f $_, (curl.exe -s -o NUL -w "%{http_code}" --max-time 20 $_ 2>&1) }
        } `
        -Hint {
            param($text)
            $r = Get-Reachability $text
            if ($r.Auth) { Write-Mark 'NG' '407（認証付きプロキシ）。IT部門へ申請（10章）'; return 'NG' }
            if ($r.Bad -gt 0) {
                Write-Mark 'NG' "到達できていないホストが $($r.Bad) 件ある（10章の申請対象）"
                return 'NG'
            }
            Write-Mark 'OK' "$($r.OK) ホストすべてTLSまで到達している"
            return 'OK'
        }

    New-Step -Id '3-4-2' -Ch '3' -Title '到達性の確認（システム設定の経路 / ブラウザ・VS Code相当）' -Kind auto `
        -Purpose '3-4-1と食い違ったら、それが原因の切り分けになる' `
        -Expect 'curlと同じ結果か。違う場合は下に出る判定と参考を読む' `
        -Show '3-4-1と同じ10ホストへ Invoke-WebRequest で接続し、HTTPステータスを見る' `
        -Cmd {
            # PowerShell 5.1 の Invoke-WebRequest は進捗バーの描画で極端に遅くなる。
            # 実測で1ホストあたり 31.44秒 → 1.99秒。10ホストで1分半以上の差になり、
            # 画面共有では無音の待ちになるため、この間だけ止める。
            $prev = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            try {
                foreach ($u in $script:ReachHosts) {
                    try { "{0,-45} {1}" -f $u, (Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 20).StatusCode }
                    catch { "{0,-45} {1}" -f $u, $_.Exception.Message }
                }
            } finally { $ProgressPreference = $prev }
        } `
        -Hint {
            param($text)
            Write-Mark '参考' '403や404は「到達成功」。文面で返ってきても落ちとは数えない（3-3）'
            $r = Get-Reachability $text
            if ($r.Auth) { Write-Mark 'NG' '407（認証付きプロキシ）。IT部門へ申請（10章）'; return 'NG' }
            if ($r.Bad -gt 0) {
                Write-Mark 'NG' "到達できていないホストが $($r.Bad) 件ある。3-4-1との食い違いは3-6-aで判定する"
                return 'NG'
            }
            Write-Mark 'OK' "$($r.OK) ホストすべてTLSまで到達している"
            return 'OK'
        }

    New-Step -Id '3-4-3' -Ch '3' -Title '教材の配布リンク（OneDrive）の到達性' -Kind ask `
        -Purpose '8-3の配布経路がこの機材から開けるか' `
        -Ask '共有リンクのURLを貼る（未確定ならEnterでスキップ）。貼った場合は続けて到達確認を行う'

    New-Step -Id '3-5-a' -Ch '3' -Title 'claude.aiへのログイン（手動）' -Kind manual `
        -Purpose 'Claude Codeの認証はブラウザを経由するため、ブラウザ側が通る必要がある' `
        -Show @"
  1. Edgeで https://claude.ai を開く
  2. ログインする（メール＋コード、またはSSO）
  3. チャットを1往復する
"@ `
        -Expect 'ログインでき、応答が返ること'

    New-Step -Id '3-5-b' -Ch '3' -Title 'ローカル通信（127.0.0.1）の迂回' -Kind auto `
        -Purpose 'ここがプロキシに投げられるとSwagger UIの確認で詰まる' `
        -Expect 'Trueであること' `
        -Cmd {
            [System.Net.WebRequest]::GetSystemWebProxy().IsBypassed([Uri]'http://127.0.0.1:8000/')
        } `
        -Hint {
            param($text)
            if ($text -match 'False') {
                Write-Mark 'NG' '迂回されない。環境変数を設定する場合はNO_PROXYにlocalhost,127.0.0.1,::1 を必ず入れる'
                return 'NG'
            } else {
                Write-Mark 'OK' '迂回される。Swagger UIの表示は問題ない'
                return 'OK'
            }
        }

    New-Step -Id '3-6-a' -Ch '3' -Title '判定ケース（3-4の結果から決まる）' -Kind auto `
        -Purpose '受講者に案内する内容が、ここで決まる。人が選ぶのではなく3-4の結果から導く' `
        -Expect 'A〜Dのいずれか。3-4を実施していなければ「判定できない」' `
        -Show '3-4-1（環境変数の経路）と3-4-2（システム設定の経路）の結果を数え、ケースを判定する' `
        -Cmd {
            $curl = $script:Captured['3-4-1']
            $ps = $script:Captured['3-4-2']
            if (-not $curl -or -not $ps) {
                '判定できない: 3-4-1 / 3-4-2 の結果が無い（3-4を実施してから戻る）'
                return
            }
            $c = Get-Reachability $curl
            $p = Get-Reachability $ps
            "環境変数の経路（curl）      到達 $($c.OK) / 落ち $($c.Bad)"
            "システム設定の経路（PS）    到達 $($p.OK) / 落ち $($p.Bad)"
            ''
            if ($c.Auth -or $p.Auth) {
                'ケースD: 407（認証付きプロキシ）が返っている'
                '  → 当日対応では解決しない。IT部門に例外設定を申請する（10章）'
            } elseif ($c.Bad -eq 0 -and $p.Bad -eq 0) {
                'ケースA: 両系統ともすべて到達している'
                '  → 受講者への設定案内は不要。01-01手順書のプロキシ節は不要と口頭で伝える'
            } elseif ($c.Bad -gt 0 -and $p.Bad -eq 0) {
                'ケースB/C: システム設定の経路は通るが、環境変数の経路が通らない'
                '  → 受講者の手順書に環境変数の設定を載せる。実値は3-2-3で判明したものを使う'
            } elseif ($c.Bad -eq 0 -and $p.Bad -gt 0) {
                '環境変数の経路のみ通っている'
                '  → ブラウザ側が通るかを3-5で必ず確認する'
            } else {
                '両系統とも落ちている'
                '  → 遮断か未設定。落ちたホストを10章の申請に上げる'
            }
            ''
            'ケースE（TLS傍受）は 4-3-08 の pip install の結果で判定する'
        } `
        -Hint {
            param($text)
            if ($text -match '判定できない') { return '保留' }
            if ($text -match 'ケースA') { return 'OK' }
            if ($text -match 'ケースD|両系統とも落ちている') { return 'NG' }
            return '保留'
        }

    # ====================== 4章 EShopの通し実行 ======================

    New-Step -Id '4-0' -Ch '4' -Title '作業フォルダの確認' -Kind info `
        -Purpose 'ここから先はファイルを作る。場所を先に確認する' `
        -Show '実行時に表示する'

    New-Step -Id '4-3-01' -Ch '4' -Title 'Claude Codeのインストール' -Kind change -TimeKey 'install' `
        -Purpose '受講者も同じコマンドを実行する（01-02）' `
        -Expect 'スクリプトの取得と実体のダウンロードの両方が通る' `
        -Show @"
  irm https://claude.ai/install.ps1 | iex

  Anthropicが公式に案内しているインストール方法（01-02-セットアップ手順.md に記載）。
  取得元は claude.ai、インストーラ本体の配布元は downloads.claude.ai。
  ユーザー領域に入るため管理者権限は不要。7-2で /logout と設定の削除を行う。
"@ `
        -Cmd {
            irm https://claude.ai/install.ps1 | iex
            # インストーラはUser PATHを更新するが、起動済みのこのプロセスには反映されない。
            # 直後の 4-3-02 が「入っていない」と誤って見えるのを防ぐ。
            # 丸ごと置き換えるとプロセス固有のPATH（有効化済みのvenv など）が落ちるため、後ろに足す。
            $add = @([Environment]::GetEnvironmentVariable('PATH', 'Machine'), [Environment]::GetEnvironmentVariable('PATH', 'User')) -ne $null
            $env:PATH = (@($env:PATH.TrimEnd(';')) + $add) -join ';'
            'このプロセスのPATHにMachineとUserの分を足した'
            # 公式インストーラが User PATH を更新しないことがある（「not in your PATH」と
            # 自分で案内してくる）。そのときは Machine/User を読み直しても拾えないので、
            # 既知の置き場を足す。受講者にも同じ現象が出るため、11章で01-02へPATH追加の
            # 手順を入れる判断材料になる。
            $bin = Join-Path $env:USERPROFILE '.local\bin'
            if ((Test-Path $bin) -and (($env:PATH -split ';') -notcontains $bin)) {
                $env:PATH = "$bin;$env:PATH"
                "インストーラがUser PATHに入れていないため、このプロセスに足した: $bin"
            }
        } `
        -SkipImpact 'スキップすると 4-3-02〜4-3-04（版の記録・ログイン・VS Code拡張）が実施できない'

    New-Step -Id '4-3-02' -Ch '4' -Title 'Claude Codeの版' -Kind auto `
        -Expect '版を記録する（本番と同一かを12章で照合する）' `
        -Show 'claude --version（解決できない場合は既知の置き場も見る）' `
        -Cmd {
            $v = try { claude --version 2>&1 } catch { $null }
            if ($v) { $v } else { 'claudeコマンドを解決できない' }
            $exe = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
            if (Test-Path $exe) { "実体あり: $exe" }
        } `
        -Hint {
            param($text)
            if ($text -match '(?m)^\s*\d+\.\d+') { Write-Mark 'OK' '版を取得できた'; return 'OK' }
            if ($text -match '実体あり:') {
                Write-Mark '保留' '導入されているがPATHから解決できない。受講者にも同じ現象が出る'
                Write-Host '        インストーラがUser PATHを更新しない機材。11章で01-02にPATH追加の手順を入れる' -ForegroundColor Yellow
                Write-Host '        このターミナルに足す: $env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"' -ForegroundColor Yellow
                return '保留'
            }
            Write-Mark 'NG' 'claudeを解決できない。導入に失敗したか、PATHが通っていない'
            Write-Host '        4-3-01 をスキップしたならここもNGでよい。実行したなら新しいターミナルで試す' -ForegroundColor Red
            return 'NG'
        }

    New-Step -Id '4-3-03' -Ch '4' -Title 'Claude Codeの起動とログイン（手動）' -Kind manual `
        -Purpose '対話セッションになるため、このスクリプトの外で行う' `
        -Show @"
  別のターミナルを開いて実行する:
    claude

  ブラウザが開くので認証を完了させる。
  そのまま対話中に /status を実行し、Proxy行が想定どおりかを見る。
"@ `
        -Expect 'ブラウザ認証まで完了し、/status のProxy行が想定どおり'

    New-Step -Id '4-3-04' -Ch '4' -Title 'VS Code拡張の導入とサインイン（手動）' -Kind manual `
        -Show @"
  1. VS Codeの拡張ビューで「Claude Code for VS Code」を検索して導入する
  2. Claude CodeパネルのSign inで認証する
"@ `
        -Expect 'インストール完了とサインインまで到達する（marketplaceとvsassetsの両方が必要）'

    New-Step -Id '4-3-05' -Ch '4' -Title 'リポジトリのclone' -Kind auto -TimeKey 'clone' `
        -Purpose 'github.com への到達をここで実測する' `
        -Expect '成功すること。所要時間を記録する（社内実測1.2秒）' `
        -Show 'git clone https://github.com/SEC-Online-Boot-Camp/EShop.git' `
        -Cmd {
            # 作業フォルダを用意できないまま進むと、カレントディレクトリにcloneしてしまう
            if (-not (Test-Path $script:WorkRoot -PathType Container)) {
                try { New-Item -ItemType Directory -Force -Path $script:WorkRoot -ErrorAction Stop | Out-Null }
                catch { "作業フォルダを作れない: $($script:WorkRoot)`n$($_.Exception.Message)"; return }
            }
            if (-not (Test-Path $script:WorkRoot -PathType Container)) {
                "作業フォルダが用意できていない: $($script:WorkRoot)（-WorkDir で指定し直す）"
                return
            }
            Push-Location $script:WorkRoot
            try {
                if (Test-Path $script:RepoDir) { "既に存在するためcloneをスキップ: $($script:RepoDir)"; return }
                # git は進捗を標準エラーに書く。2>&1 のままだと ErrorRecord になり、
                # 成功しているのに画面へ赤いブロックが出て手が止まる。文字列にする。
                git clone https://github.com/SEC-Online-Boot-Camp/EShop.git 2>&1 | ForEach-Object { "$_" }
            } finally { Pop-Location }
        } `
        -Hint {
            param($text)
            if (Test-Path (Join-Path $script:RepoDir 'backend')) {
                Write-Mark 'OK' 'cloneできている（backendが見える）'
                return 'OK'
            }
            Write-Mark 'NG' 'cloneできていない。github.com への到達を3-4で確認する'
            return 'NG'
        }

    New-Step -Id '4-3-06' -Ch '4' -Title '仮想環境の作成' -Kind auto -TimeKey 'venv' `
        -Expect '.venv が作られる（社内実測8.5秒）' `
        -Show 'cd backend ; python -m venv .venv' `
        -Cmd { Invoke-InSrc { python -m venv .venv 2>&1; "作成先: $(Join-Path $PWD '.venv')" } } `
        -Hint {
            param($text)
            $p = Join-Path $script:SrcDir '.venv\Scripts\python.exe'
            if (Test-Path $p) { Write-Mark 'OK' '.venv\Scripts\python.exe ができている'; return 'OK' }
            Write-Mark 'NG' '仮想環境（.venv）ができていない。ここで止める'
            Write-Host '        このまま進むと貸与機のPythonに pip install してしまうため、4-3-08以降は実行しない' -ForegroundColor Red
            return 'NG'
        }

    New-Step -Id '4-3-07' -Ch '4' -Title '仮想環境の有効化（activateの可否）' -Kind auto `
        -Purpose '実行ポリシーで .ps1 が禁止されていると失敗する。代替1行が効くかをここで確定する' `
        -Expect '(.venv) 相当の状態になること。activateが失敗した場合は代替1行で通ること' `
        -Show @"
  .venv\Scripts\activate
  （失敗する場合の代替1行 = 01-01手順書に記載のもの）
  `$env:VIRTUAL_ENV="`$PWD\.venv"; `$env:PATH="`$env:VIRTUAL_ENV\Scripts;`$env:PATH"; function prompt {"(.venv) PS `$PWD> "}

  受講者は末尾の function prompt が出す (.venv) の表示で成功を判断する。
  ここでは python と pytest の解決先で判定するため、prompt は変えない。
"@ `
        -Cmd {
            Invoke-InSrc {
                $ps1 = '.\.venv\Scripts\Activate.ps1'
                $ok = $false
                try {
                    . $ps1
                    $ok = $true
                    'activate（.ps1）が通った'
                } catch {
                    "activate（.ps1）は失敗した: $($_.Exception.Message)"
                }
                if (-not $ok) {
                    $env:VIRTUAL_ENV = "$PWD\.venv"
                    $env:PATH = "$env:VIRTUAL_ENV\Scripts;$env:PATH"
                    '代替1行を適用した（01-01手順書の記載どおり）'
                }
                "python => $((Get-Command python -ErrorAction SilentlyContinue).Source)"
                # pytest が入るのは次の 4-3-08。ここで Get-Command を引くと、グローバルに
                # pytest がある機材では venv の外のパスを拾ってしまう。確認は 4-3-08 に任せる。
                'pytest => 4-3-08 のpip installで入るため、ここでは確認しない'
            }
        } `
        -Hint {
            param($text)
            if ($text -match 'activate（\.ps1）は失敗した') {
                # 結論は2-1-cで見たグループポリシーの有無で変わる。縛りが無ければ
                # Set-ExecutionPolicy -Scope CurrentUser が効くので、01-01手順書の2段目を
                # 消してはいけない。消すと受講者はターミナルを開くたびに代替1行を打つことになる。
                $pol = $script:Captured['2-1-c']
                if (-not $pol) {
                    Write-Mark '参考' '2-1-cを実施していないため、手順書を絞れるかは判定できない（11章へ記録）'
                } elseif ($pol -match '(?m)^\s*(MachinePolicy|UserPolicy)\s+(?!Undefined)\S+') {
                    Write-Mark '参考' 'グループポリシーで縛られている。01-01手順書は代替1行だけに絞る（11章へ記録）'
                } else {
                    Write-Mark '参考' 'グループポリシーの縛りは無い。Set-ExecutionPolicy -Scope CurrentUser で直るため、'
                    Write-Host '        01-01手順書の2段目は残す。代替1行は3段目のままにする（11章へ記録）' -ForegroundColor DarkGray
                }
            }
            if ($text -notmatch '\.venv') {
                Write-Mark 'NG' 'python/pytest が .venv 配下を指していない。ここが揃わないと以降が別環境になる'
                return 'NG'
            }
            # -ExecutionPolicy Bypass で起動していると（VS Codeの統合ターミナルも既定でそうなる
            # ことがある）Process スコープが効いて Activate.ps1 が通ってしまう。受講者は素の
            # ターミナルなので、この結果をそのまま手順書へ反映できない。
            $pol = $script:Captured['2-1-c']
            if ($pol -match '(?m)^\s*Process\s+(Bypass|Unrestricted)') {
                Write-Mark '保留' 'Process スコープが Bypass のため、activateの可否は受講者の環境を表さない'
                Write-Host '        受講者は素のターミナルで実行する。2-1-c の LocalMachine と CurrentUser で判断する' -ForegroundColor Yellow
                Write-Host '        GPOの縛りが無ければ Set-ExecutionPolicy -Scope CurrentUser が効くので、01-01手順書の2段目は残す' -ForegroundColor Yellow
                return '保留'
            }
            return 'OK'
        }

    New-Step -Id '4-3-08' -Ch '4' -Title '依存パッケージのインストール' -Kind auto -TimeKey 'pip' `
        -Purpose '最も伸びやすい。TLS傍受があるとここだけ証明書エラーで落ちる。ケースEの判定はここで行う' `
        -Expect '成功すること（社内実測31.4秒）' `
        -Show @"
  pip install -r requirements.txt

  precheckでは --retries 1 を足す。pipの既定は5回再試行するため、到達できない機材だと
  十数分無反応になる。成功する機材では所要時間は変わらないので、6章の実測にも使える。
"@ `
        -Cmd {
            Invoke-InSrc {
                & (Get-VenvPython) -m pip install --retries 1 -r requirements.txt 2>&1
                # 4-3-07 の時点では未導入なので、入ったここで確認する（事前確認書 3-1）。
                # .venv の外を指していると、以降のテストが別環境で走る。
                $pt = (Get-Command pytest -ErrorAction SilentlyContinue).Source
                if (-not $pt) { 'pytest => 解決できない。.venv が有効になっていない可能性がある' }
                elseif ($pt -notlike '*\.venv\*') { "pytest => $pt （.venv の外を指している。別環境のpytestが優先されている）" }
                else { "pytest => $pt" }
            }
        } `
        -Hint {
            param($text)
            if ($text -match '仮想環境が無い') {
                Write-Mark 'NG' '仮想環境が無いため実行していない。4-3-06 を先に通す'
                return 'NG'
            }
            if ($text -match 'CERTIFICATE_VERIFY_FAILED|SSLError') {
                Write-Mark 'NG' 'TLS傍受あり（ケースE）。pipだけが証明書で落ちるのが典型'
                Write-Host '        付録Cの対処へ。検証の無効化は使わない。証明書の名称はIT部門に確認（10章）' -ForegroundColor Red
            } elseif ($text -match 'Successfully installed|Requirement already satisfied') {
                Write-Mark 'OK' '証明書エラーは出ていない。TLS傍受はなし（またはCAが配布済み）と判定できる'
            }
            if ($text -match 'Failed building wheel|error: subprocess-exited-with-error') {
                Write-Mark 'NG' 'wheelが無くソースビルドに落ちている。Pythonの版を合わせる判断が必要（4-2）'
            }
            if ($text -match '(?m)^\s*ERROR:' -or $text -match 'CERTIFICATE_VERIFY_FAILED|SSLError|Failed building wheel') { return 'NG' }
            if ($text -match 'Successfully installed|Requirement already satisfied') { return 'OK' }
            return $null
        }

    New-Step -Id '4-3-09' -Ch '4' -Title '初期データの投入' -Kind auto -TimeKey 'seed' `
        -Expect '「ユーザー2件・商品5件を投入しました。」（社内実測1.9秒）' `
        -Show 'python -m app.seed' `
        -Cmd { Invoke-InSrc { & (Get-VenvPython) -m app.seed 2>&1 } } `
        -Hint {
            param($text)
            if ($text -match '仮想環境が無い') {
                Write-Mark 'NG' '仮想環境が無いため実行していない。4-3-06 を先に通す'
                return 'NG'
            }
            if ($text -match 'ユーザー2件・商品5件') { Write-Mark 'OK' '期待どおりの件数'; return 'OK' }
            if ($text -match 'すでにデータが投入されています') {
                Write-Mark '保留' 'DBが残っているため投入をスキップした。件数を確認できていない'
                Write-Host '        やり直す場合はbackendの ecommerce.db を消してから再実行する' -ForegroundColor Yellow
                return '保留'
            }
            Write-Mark 'NG' '期待する件数（ユーザー2件・商品5件）が出ていない'
            return 'NG'
        }

    New-Step -Id '4-3-10' -Ch '4' -Title 'サーバー起動とSwagger UIの表示' -Kind auto `
        -Purpose 'アプリが起動して応答を返すことを確かめる。あわせてループバックの迂回も測る' `
        -Expect 'http://127.0.0.1:8000/docs が200を返す' `
        -Show @"
  別のターミナルで起動したままにする場合:

    cd $script:SrcDir
    .venv\Scripts\uvicorn.exe app.main:app --reload

$script:VenvNote
  → ブラウザで http://127.0.0.1:8000/docs を開く

  このスクリプトでは、サーバーを裏で起動して /docs のステータスを2通りで取り、最後に停止する。
  仮想環境の python を絶対パスで呼ぶので、こちらは activate が要らない。
  ・プロキシを使わない（--noproxy '*'）… サーバーが起動して応答を返すか
  ・環境変数の経路をそのまま使う        … 127.0.0.1 がプロキシに投げられていないか

  ブラウザが使うのはシステム設定の経路なので、その判定は 3-5-b が正本になる。
"@ `
        -Cmd {
            Invoke-InSrc {
                # 既に8000番が塞がっていると、古いサーバーに当たって200が返り誤ってOKになる
                $busy = $false
                try {
                    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 8000)
                    $l.Start(); $l.Stop()
                } catch { $busy = $true }
                if ($busy) {
                    '8000番が既に使われている。別のサーバーに当たるため判定できない'
                    '  → 起動済みのuvicornを止めてからやり直す'
                    return
                }
                $py = Get-VenvPython
                $log = Join-Path $env:TEMP "precheck-uvicorn-$PID.log"
                $err = Join-Path $env:TEMP "precheck-uvicorn-$PID.err"
                # 隠しウィンドウでの起動は監視側から見て説明が要る形になるため -NoNewWindow にする。
                # あわせて出力を受け取り、起動に失敗した理由が記録に残るようにする。
                $proc = Start-Process -FilePath $py -ArgumentList '-m', 'uvicorn', 'app.main:app' `
                    -WorkingDirectory (Get-Location).Path -PassThru -NoNewWindow `
                    -RedirectStandardOutput $log -RedirectStandardError $err
                try {
                    $code = ''
                    # 貸与機はウイルス対策の常駐で初回importが延びる。20秒では足りないことがある
                    for ($i = 0; $i -lt 40; $i++) {
                        Start-Sleep -Seconds 1
                        if ($proc.HasExited) { break }
                        $code = (curl.exe -s -o NUL -w "%{http_code}" --max-time 5 --noproxy '*' http://127.0.0.1:8000/docs 2>&1)
                        if ($code -eq '200') { break }
                    }
                    "http://127.0.0.1:8000/docs => $code  （プロキシを使わずに確認）"
                    if ($code -eq '200') {
                        # ここだけ --noproxy を外す。環境変数の経路でループバックが迂回されるかの実測。
                        $via = (curl.exe -s -o NUL -w "%{http_code}" --max-time 10 http://127.0.0.1:8000/docs 2>&1)
                        if ($via -eq '200') {
                            "環境変数の経路でも200。127.0.0.1 はプロキシに投げられていない"
                        } else {
                            "環境変数の経路では $via。127.0.0.1 がプロキシに投げられている"
                            # ブラウザはシステム設定の経路を使う。3-5-b が正本なので、そこを見て
                            # 言い分ける。3-6-a のケース判定は3-4（外部ホスト）だけを見ているため、
                            # ここで「案内が要る」と言い切ると記録の中で食い違う。
                            $bp = $script:Captured['3-5-b']
                            if ($bp -match 'True') {
                                '  → ブラウザは影響を受けない（3-5-b=True）。4-5 の確認は通る'
                                '  → 環境変数の経路でループバックに繋ぐ手順は演習に無いため、受講者への案内は不要'
                            } elseif ($bp -match 'False') {
                                '  → ブラウザも迂回されない（3-5-b=False）。NO_PROXYにループバックを足す案内が要る'
                            } else {
                                '  → 3-5-b を実施していないため、ブラウザ側への影響は判定できない'
                            }
                        }
                        'ブラウザでも開いて画面を確認する（起動したままにしたい場合は、上の手順で別のターミナルから起動し直す）'
                    } else {
                        'サーバーが応答を返していない。起動時の出力を見る:'
                        foreach ($f in $err, $log) {
                            if (Test-Path $f) {
                                $tail = @(Get-Content $f -Tail 15 -ErrorAction SilentlyContinue)
                                if ($tail.Count -gt 0) { "  --- $(Split-Path $f -Leaf) ---"; $tail | ForEach-Object { "  $_" } }
                            }
                        }
                    }
                } finally {
                    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force; 'サーバーを停止した' }
                    # ハンドルが解放される前に消すと共有違反で失敗し、ログが貸与機に残る。
                    # -ErrorAction SilentlyContinue にしてあるので失敗しても気づけないため、先に待つ。
                    if ($proc) { $proc.WaitForExit(3000) | Out-Null }
                    Remove-Item $log, $err -Force -ErrorAction SilentlyContinue
                    foreach ($f in $log, $err) {
                        if (Test-Path $f) { "一時ファイルを消せなかった: $f（7-3で手で消す）" }
                    }
                }
            }
        } `
        -Hint {
            param($text)
            if ($text -match '仮想環境が無い') {
                Write-Mark 'NG' '仮想環境が無いため実行していない。4-3-06 を先に通す'
                return 'NG'
            }
            if ($text -match '8000番が既に使われている') {
                Write-Mark '保留' '判定できない。8000番を空けてからやり直す'
                return '保留'
            }
            if ($text -match 'docs => 200') {
                if ($text -match 'プロキシに投げられている可能性') {
                    Write-Mark '保留' 'サーバーは起動した。ただしループバックがプロキシに向いている'
                    Write-Host '        ブラウザ側の判定は 3-5-b を見る。受講者への案内が要るかはそこで決める' -ForegroundColor Yellow
                    return '保留'
                }
                Write-Mark 'OK' 'サーバーが起動して応答を返した。ループバックの迂回も問題ない'
                return 'OK'
            }
            Write-Mark 'NG' '200が返っていない。上の起動時の出力を見る'
            return 'NG'
        }

    New-Step -Id '4-3-11' -Ch '4' -Title 'テストの実行（mainの基準線）' -Kind auto -TimeKey 'pytest-main' `
        -Expect '全件PASS。mainの基準は54件（社内実測8.6秒）' `
        -Show 'pytest' `
        -Cmd { Invoke-InSrc { & (Get-VenvPython) -m pytest 2>&1 } } `
        -Hint {
            param($text)
            if ($text -match '仮想環境が無い') {
                Write-Mark 'NG' '仮想環境が無いため実行していない。4-3-06 を先に通す'
                return 'NG'
            }
            if ($text -match '(\d+)\s+passed') {
                $n = [int]$Matches[1]
                if ($n -eq 54) { Write-Mark 'OK' "54件PASS。基準どおり" }
                else { Write-Mark 'NG' "${n}件PASS。基準の54件と違う" }
            }
            if ($text -match '(\d+)\s+failed') { Write-Mark 'NG' "失敗 $($Matches[1]) 件。mainでは全件PASSが期待値" }
            if ($text -match '(?m)(\d+)\s+passed' -and [int]$Matches[1] -eq 54 -and $text -notmatch '\d+\s+failed') { return 'OK' }
            return 'NG'
        }

    New-Step -Id '4-3-12' -Ch '4' -Title 'VS Code拡張の版' -Kind auto `
        -Purpose '5-8（拡張でも同じか）は拡張の版に依存する。CLIだけ12章で照合できて拡張ができないのは非対称' `
        -Expect 'Claude Codeの拡張の版を記録する（本番と同一かを12章で照合する）' `
        -Show 'code --list-extensions --show-versions（照合用の2行を先に出す）' `
        -Cmd {
            $raw = @(code --list-extensions --show-versions 2>&1 | ForEach-Object { "$_" })
            $cl = @($raw | Where-Object { $_ -match '(?i)claude-code' })
            $py = @($raw | Where-Object { $_ -match '(?i)^ms-python\.python@' })
            "Claude拡張 : $(if ($cl.Count -gt 0) { $cl -join ' ' } else { '無し' })"
            # Python拡張が無ければ、ターミナルを開くたびの自動activate（拡張の
            # python.terminal.activateEnvironment に由来）は起きない。01-01手順2の注記が
            # 当日発生するかの判断材料になるので、一覧を絞らずここに出す。
            "Python拡張 : $(if ($py.Count -gt 0) { $py -join ' ' } else { '無し（ターミナルの自動activateは起きない）' })"
            # code の stderr が混ざるため、拡張の形をした行だけを数える。ただし出力からは落とさない
            # （Hint の「解決できない」判定がこのテキストを見ている）。
            $exts = @($raw | Where-Object { $_ -match '^[\w-]+\.[\w-]+@' })
            "導入済み   : $($exts.Count)件"
            $raw | ForEach-Object { "  $_" }
        } `
        -Hint {
            param($text)
            if ($text -match '(?i)not recognized|認識されません|CommandNotFound') {
                # 2-2-a と同じ原因（PATHに追加せずにVS Codeを入れた）。機材の不具合ではなく、
                # 版は拡張ビューから手でも取れるので、2-2-a と同じ 保留 にそろえる。
                Write-Mark '保留' 'codeがPATHに無い（2-2-aと同じ）。講座ではcodeコマンドを使わないため実害は無い'
                Write-Host '        版はVS Codeの拡張ビューで読める。手で記録して12章の照合に使う' -ForegroundColor Yellow
                return '保留'
            }
            # 'claude' だと「Claude拡張 : 無し」のラベルに当たってしまう。
            # 'claude-code' はラベルに当たらず、発行者名が変わっても拾える。
            if ($text -notmatch '(?i)claude-code') {
                Write-Mark 'NG' 'Claude Codeの拡張が一覧に無い。4-3-04（拡張の導入）を確認する'
                return 'NG'
            }
            Write-Mark 'OK' '拡張の版を取得できた'
            return 'OK'
        }

    New-Step -Id '4-4-01' -Ch '4' -Title 'No.2成果物の配置（ダミーで代用）' -Kind change `
        -Purpose 'No.3の手順書はNo.2の成果物を参照する。無いと4-4の手順6以降と5章の#5が実行できない' `
        -Expect 'docs/要件整理メモ.md が置かれ、docs/基本設計書.md の末尾にクーポン機能の章が追記される' `
        -Show @"
  Copy-Item <rehearsalブランチ>\docs-template\要件整理メモ.md docs\
  docs\基本設計書.md の末尾に <rehearsalブランチ>\docs-template\基本設計書.md を追記する

  リハーサルではNo.2の演習を行わないため、rehearsalブランチのダミー成果物で代用する。
  docs/基本設計書.md は配布時から入っている既存機能の設計書で、受講者はこれに追記する。
  上書きせず追記するのはそのためで、すでに追記済みなら二重には足さない。
  中身の妥当性は問わず、手順が実行できるかの確認が目的。
  解答例は講師専用資料なので、この経路では使わない。
"@ `
        -Cmd {
            Invoke-InRepo {
                $tpl = Join-Path $script:MaterialRoot 'docs-template'
                $memo = Join-Path $tpl '要件整理メモ.md'
                $add = Join-Path $tpl '基本設計書.md'
                if (-not (Test-Path $memo) -or -not (Test-Path $add)) { "docs-template が見つからない: $tpl（-MaterialDir で指定する）"; return }
                $doc = Join-Path (Get-Location).Path 'docs\基本設計書.md'
                if (-not (Test-Path $doc)) { "配布時の設計書が無い: $doc（EShop が古いか、ブランチが違う）"; return }
                New-Item -ItemType Directory -Force docs | Out-Null
                Copy-Item $memo (Join-Path 'docs' '要件整理メモ.md') -Force
                $utf8 = New-Object System.Text.UTF8Encoding $false
                $body = [System.IO.File]::ReadAllText($add, $utf8).TrimStart([char]0xFEFF)
                $heading = ($body -split "`r?`n" | Where-Object { $_ -match '^#' } | Select-Object -First 1)
                $now = [System.IO.File]::ReadAllText($doc, $utf8)
                if ($heading -and $now.Contains($heading)) {
                    "追記済みのため足さない: $heading"
                } else {
                    [System.IO.File]::AppendAllText($doc, "`n" + $body, $utf8)
                    "追記した: $heading"
                }
                Get-ChildItem docs | ForEach-Object { "  {0}  {1} bytes" -f $_.Name, $_.Length }
            }
        } `
        -SkipImpact 'スキップすると 4-4-03（成果物の確認）以降と5章の#5が実施できない'

    New-Step -Id '4-4-02' -Ch '4' -Title 'couponブランチの取得と切り替え' -Kind auto -TimeKey 'fetch' `
        -Purpose 'ここで再びネットワークを使う。No.1が通っても省略しない' `
        -Expect 'git branch --show-current がcoupon' `
        -Show 'git fetch origin ; git switch coupon ; git branch --show-current' `
        -Cmd {
            Invoke-InRepo {
                git fetch origin 2>&1 | ForEach-Object { "$_" }
                git switch coupon 2>&1 | ForEach-Object { "$_" }
                "current = $(git branch --show-current)"
            }
        } `
        -Hint {
            param($text)
            if ($text -match 'current = coupon') { Write-Mark 'OK' 'couponに切り替わっている'; return 'OK' }
            Write-Mark 'NG' 'couponに切り替わっていない'
            return 'NG'
        }

    New-Step -Id '4-4-03' -Ch '4' -Title '切り替え後のファイル確認' -Kind auto `
        -Purpose 'couponへの切り替えでcoupon.pyが増え、No.2の成果物（要件整理メモと基本設計書への追記）が残っていることを確認する' `
        -Expect '両方がbackendから見つかること' `
        -Show @"
  backendで : Get-ChildItem app\coupon.py
  backendで : Get-ChildItem ..\docs

  03-01の手順0と同じ場所・同じ書き方で見る。docsはEShop直下にあるため backend からは ..\docs。
"@ `
        -Cmd {
            # Select-Object で出すと、PowerShell の表組みが1つ目のオブジェクトで列を決めるため、
            # FullName,Length のあとの Name,Length が空欄になり、Hint がファイル名を見つけられない。
            # 文字列にして切り離す。
            Invoke-InSrc {
                'backend:'
                Get-ChildItem 'app\coupon.py' -ErrorAction SilentlyContinue |
                    ForEach-Object { "  {0}  {1} bytes" -f $_.Name, $_.Length }
                'backend から ..\docs:'
                Get-ChildItem '..\docs' -ErrorAction SilentlyContinue |
                    ForEach-Object { "  {0}  {1} bytes" -f $_.Name, $_.Length }
                # 基本設計書.md は配布時からあるので、有無ではなく追記されているかを見る
                $doc = '..\docs\基本設計書.md'
                $added = (Test-Path $doc) -and ((Get-Content $doc -Raw -Encoding UTF8) -match '(?m)^#+ .*クーポン')
                "基本設計書.md のクーポン機能の章: $(if ($added) { 'あり' } else { 'なし' })"
            }
        } `
        -Hint {
            param($text)
            $hasCoupon = $text -match 'coupon\.py'
            $hasDocs = ($text -match '要件整理メモ') -and ($text -match 'クーポン機能の章: あり')
            if (-not $hasCoupon) {
                Write-Mark 'NG' 'app\coupon.py が無い。couponへの切り替え（4-4-02）を確認する'
                return 'NG'
            }
            if ($hasDocs) {
                Write-Mark 'OK' '両方ある（03-01の手順0どおり、backendから通る）'
                return 'OK'
            }
            # 4-4-01 を実施していなければ docs は無いのが当然なので、NGではなく保留にする
            $placed = $script:Results | Where-Object { $_.Id -eq '4-4-01' -and $_.Verdict -eq 'OK' }
            if ($placed) {
                Write-Mark 'NG' '4-4-01は実施済みなのにdocsの成果物が無い。配置先を確認する'
                return 'NG'
            }
            Write-Mark '保留' 'docsが無い。4-4-01（成果物の配置）を実施していないため判定できない'
            Write-Host '        coupon.py は見つかっているので、切り替え自体は成功している' -ForegroundColor Yellow
            return '保留'
        }

    New-Step -Id '4-4-04' -Ch '4' -Title 'DBの作り直しとシード投入' -Kind auto -TimeKey 'seed-no3' `
        -Expect '「ユーザー2件・商品5件・クーポン6件を投入しました。」' `
        -Show 'Remove-Item ecommerce.db -ErrorAction SilentlyContinue ; python -m app.seed' `
        -Cmd {
            Invoke-InSrc {
                Remove-Item ecommerce.db -ErrorAction SilentlyContinue
                & (Get-VenvPython) -m app.seed 2>&1
            }
        } `
        -Hint {
            param($text)
            if ($text -match '仮想環境が無い') {
                Write-Mark 'NG' '仮想環境が無いため実行していない。4-3-06 を先に通す'
                return 'NG'
            }
            if ($text -notmatch 'クーポン') {
                Write-Mark 'NG' 'クーポン件数が出ていない。couponブランチに切り替わっているか確認する'
                return 'NG'
            }
            if ($text -match 'ユーザー2件・商品5件・クーポン6件') { Write-Mark 'OK' '期待どおりの件数'; return 'OK' }
            if ($text -notmatch 'ユーザー' -or $text -notmatch '商品') {
                # 既存データがあるとseedはユーザーと商品の投入を飛ばし、クーポンの行だけが出る
                Write-Mark 'NG' 'ユーザーと商品の件数が出ていない。ecommerce.db の削除に失敗している可能性が高い'
                return 'NG'
            }
            Write-Mark 'NG' 'クーポンは出ているが件数が期待と違う'
            return 'NG'
        }

    New-Step -Id '4-4-05' -Ch '4' -Title '回帰試験の基準線' -Kind auto -TimeKey 'pytest-no3' `
        -Expect '55件PASS' `
        -Show 'pytest' `
        -Cmd { Invoke-InSrc { & (Get-VenvPython) -m pytest 2>&1 } } `
        -Hint {
            param($text)
            if ($text -match '仮想環境が無い') {
                Write-Mark 'NG' '仮想環境が無いため実行していない。4-3-06 を先に通す'
                return 'NG'
            }
            if ($text -match '(\d+)\s+passed') {
                $n = [int]$Matches[1]
                if ($n -eq 55) { Write-Mark 'OK' '55件PASS。基準どおり' }
                else { Write-Mark 'NG' "${n}件PASS。基準の55件と違う" }
            }
            if ($text -match '(?m)(\d+)\s+passed' -and [int]$Matches[1] -eq 55 -and $text -notmatch '\d+\s+failed') { return 'OK' }
            return 'NG'
        }

    # 4-5 を 4-4-05 と 4-4-06 の間に置いてあるのは実行順のため（couponのseedが済んでいないと
    # 注文が通らない）。記録の並びが 4-4-05 → 4-5 → 4-4-06 になるのは意図したもの。
    New-Step -Id '4-5' -Ch '4' -Title 'Swagger UIでの注文確定（手動）' -Kind manual `
        -Purpose 'pytestは別DBを使うため、ecommerce.db の削除漏れはここでしか表面化しない' `
        -Show @"
  1. 別のターミナルで起動し、http://127.0.0.1:8000/docs を開く
       cd $script:SrcDir
       .venv\Scripts\uvicorn.exe app.main:app --reload
$script:VenvNote
  2. POST /auth/login を実行し、access_tokenを控える
     （ログイン情報は backend/app/seed.py に定義されている。README.md には無い）
  3. 画面右上のAuthorizeにトークンを貼る
  4. POST /cart/items で商品を1件カートに追加する
  5. POST /orders を実行する

  500で「table orders has no column named coupon_code」が出たら、
  4-4-04 のDB削除ができていない。DBを消してseedからやり直す。
"@ `
        -Expect 'POST /orders が201を返す'

    New-Step -Id '4-4-06' -Ch '4' -Title '生成したテストの実行（手動）' -Kind manual `
        -Show @"
  03-02 の手順でAIに tests/test_coupon.py を生成させ、次を実行する:
    cd $script:SrcDir
    .venv\Scripts\pytest.exe tests/test_coupon.py -v --disable-warnings
$script:VenvNote
"@ `
        -Expect 'テストが実行できること（FAILEDは想定内）'

    New-Step -Id '4-4-07' -Ch '4' -Title 'デバッグ演習の実行（手動）' -Kind manual `
        -Show @"
  03-03 の手順で次を実行する:
    .venv\Scripts\pytest.exe --tb=no -q -rf --disable-warnings

  配布コードには意図的な欠陥が仕込まれている。失敗が出るのが正常。
  最後に引数なしのpytestが全件PASSする状態まで到達できるかを見る。
  （件数は受講者に伏せるため、ここには書かない。事前確認書の4-4を見る）
"@ `
        -Expect '意図的な欠陥に由来する失敗が出て、最後に全件PASSまで到達できる（件数は事前確認書の4-4）'

    # ====================== 5章 Claude Codeの動作確認 ======================

    New-Step -Id '5-1' -Ch '5' -Title '版の記録' -Kind auto -Site materials `
        -Purpose '5-2以降の結果がどの版で確かめたものかを残す。12章で本番当日の版と照合する' `
        -Expect 'CLIと拡張の版が記録される。貸与機（4-3-02・4-3-12）と離れていれば差も残る' `
        -Show 'claude --version と code --list-extensions --show-versions' `
        -Cmd {
            $v = @(claude --version 2>&1 | ForEach-Object { "$_" })
            "CLI         : $(if ($v.Count -gt 0) { $v -join ' ' } else { '解決できない' })"
            $raw = @(code --list-extensions --show-versions 2>&1 | ForEach-Object { "$_" })
            $cl = @($raw | Where-Object { $_ -match '(?i)claude-code' })
            "VS Code拡張 : $(if ($cl.Count -gt 0) { $cl -join ' ' } else { '無し' })"
            ''
            '貸与機の版（4-3-02・4-3-12）と離れていると、5-3・5-6・5-7・5-8 の結果が当日に'
            '当てはまらない。離れている場合は揃えてから実施するか、差を記録に残す。'
        } `
        -Hint {
            param($text)
            Write-Mark '参考' '貸与機の版と突き合わせる。とくに 5-8 は拡張の版に直接依存する'
        }

    New-Step -Id '5-2' -Ch '5' -Title 'CLAUDE.md の認識（手動）' -Kind manual -Site materials `
        -Show "  claudeの対話中に /clear のあと /context" `
        -Expect 'Memory filesに EShop\CLAUDE.md が出る'

    New-Step -Id '5-3' -Ch '5' -Title 'ルール適用前に .env が出力されるか（手動）' -Kind manual -Site materials `
        -Purpose 'ここで値が表示されないと01-03の演習前半が成立しない。最重要の確認項目' `
        -Show '  01-03-システムプロンプト設定手順.md の手順1を実施する' `
        -Expect 'ダミーの値がそのまま表示される（表示されない場合は手順書をデモ形式に切り替える判断が必要）'

    New-Step -Id '5-4' -Ch '5' -Title 'ルール適用後に出力されないか（手動）' -Kind manual -Site materials `
        -Show '  01-03 の手順4を実施する' `
        -Expect 'CLAUDE.md を理由に値を出さない'

    New-Step -Id '5-5' -Ch '5' -Title 'ファイル参照（手動）' -Kind manual -Site materials `
        -Show '  プロンプトに @docs/要件整理メモ.md を渡す（4-4-01で配置したもの）' `
        -Expect '内容を読み込む'

    New-Step -Id '5-6' -Ch '5' -Title 'ファイル作成・編集の権限プロンプト（手動）' -Kind manual -Site materials `
        -Show @"
  03-02 でテストコードを保存させる（新規作成）
  03-03 の手順3で app\ 配下の既存ファイルを編集させる（差分を見てから承認する）
"@ `
        -Expect '作成と編集それぞれで許可を求められる。表示が違うため、受講者への案内は両方そろえる'

    New-Step -Id '5-7' -Ch '5' -Title 'コマンド実行の権限プロンプト（手動）' -Kind manual -Site materials `
        -Show '  03-03 で .venv\Scripts\pytest.exe を実行させる' `
        -Expect '許可を求められる'

    New-Step -Id '5-8' -Ch '5' -Title 'VS Code拡張でも同じか（手動）' -Kind manual -Site materials `
        -Show '  5-3〜5-7 と同じ操作を拡張の右パネルで行う' `
        -Expect 'CLIと同じ結果'

    New-Step -Id '5-9' -Ch '5' -Title '.envの抽象化後にアプリが動くか' -Kind manual -Site materials `
        -Show @"
  01-04-機密情報の抽象化手順.md の手順3を実施したあと、backendでpytestを実行する。
  （このスクリプトの 4-3-11 と同じコマンド）
"@ `
        -Expect '全件PASS。DATABASE_URLは置換しない'

    New-Step -Id '5-10' -Ch '5' -Title '/security-review が使えるか（手動）' -Kind manual -Site materials `
        -Purpose '03-00のスライドで1ページ紹介し、03-03でも「時間が余ったら試す」と案内している' `
        -Show @"
  claude の対話中に /security-review を実行する（couponの変更に対して）
"@ `
        -Expect 'コマンドが存在し、レビュー結果が返る。使えない場合は03-00と03-03の案内を落とす'

    New-Step -Id '5-11' -Ch '5' -Title 'hookで既存テストへの書き込みが止まるか（手動）' -Kind manual -Site materials `
        -Purpose '03-02の手順2で、受講者がAIに作らせたhookで既存テストを守る' `
        -Show @"
  03-02の手順2のプロンプトでhookを作らせる（.claude/settings.json の作成で確認が出る）
  VS Codeで Developer: Reload Window のあと、既存の backend/tests/test_orders.py に書き足させる
  backendで : git diff --stat -- tests
"@ `
        -Expect '理由付きで止まり、git diff --stat -- tests が空。新しいテストファイルは作れる。所要（目安10〜15分）も記録する'

    # ====================== 6章 所要時間 ======================

    New-Step -Id '6' -Ch '6' -Title '所要時間の集計' -Kind info `
        -Purpose '4章で計測した値を、カリキュラムの枠と突き合わせる' `
        -Show '実行時に集計表を表示する'

    # ====================== 7章 原状復帰 ======================

    New-Step -Id '7-1' -Ch '7' -Title 'リポジトリに差分が残っていないか' -Kind auto `
        -Purpose '抽象化済みの .env が共有リポジトリに入ると以降の受講者の演習が成立しない' `
        -Expect '追跡ファイル（backend/.env・backend/.gitignore）に変更が無く、未pushのコミットも無い' `
        -Show @"
  git status --porcelain
  git diff --name-only -- backend/.env backend/.gitignore
  git log @{u}..HEAD --oneline     # 追跡ブランチとの差（couponにいてもmainと比べない）
  git remote -v
"@ `
        -Cmd {
            Invoke-InRepo {
                $enc = if ($script:ConsoleCodePage -eq 65001) { 'UTF-8' } else { "CP$($script:ConsoleCodePage)" }
                $all = @(git status --porcelain 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ })
                # docs/ の追跡ファイル（基本設計書.md）は 4-4-01 でダミーを追記したもの。No.2 で受講者が
                # 追記するのと同じ変更で、クローンごと消えるので、判定には含めずに分けて出す
                $tracked = @($all | Where-Object { $_ -notmatch '^\?\?' -and $_ -notmatch 'docs/' })
                $docsMod = @($all | Where-Object { $_ -notmatch '^\?\?' -and $_ -match 'docs/' })
                $untracked = @($all | Where-Object { $_ -match '^\?\?' })
                '--- 追跡ファイルの変更（backend/.env・backend/.gitignore など）---'
                if ($tracked.Count -eq 0) { '（変更なし）' } else { $tracked }
                if ($docsMod.Count -gt 0) {
                    '--- 4-4-01 で追記したダミー（判定に含めない。クローン削除で消える）---'
                    $docsMod
                }
                '--- 未追跡ファイル（演習の副産物。クローン削除で消える）---'
                if ($untracked.Count -eq 0) { '（なし）' } else { $untracked }
                '--- .env / .gitignore の差分 ---'
                $df = @(git diff --name-only -- backend/.env backend/.gitignore 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ })
                if ($df.Count -eq 0) { '（差分なし）' } else { $df }
                '--- 未pushのコミット ---'
                $up = (git rev-parse --abbrev-ref '@{u}' 2>&1)
                $log = @()
                if ($LASTEXITCODE -eq 0 -and $up -notmatch 'fatal') {
                    "追跡ブランチ: $up"
                    $log = @(git -c i18n.logOutputEncoding=$enc log '@{u}..HEAD' --oneline 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ })
                    if ($log.Count -eq 0) { '（なし）' } else { $log }
                } else {
                    '追跡ブランチが無い（push先が設定されていない）'
                }
                '--- push先 ---'
                git remote -v 2>&1 | ForEach-Object { "$_" }
                ''
                if ($tracked.Count -gt 0 -or $log.Count -gt 0) { '結果: 追跡ファイルの変更または未pushのコミットがある' }
                else { '結果: 追跡ファイルの変更なし・未pushなし' }
            }
        } `
        -Hint {
            param($text)
            Write-Mark '参考' 'リハーサル機からは絶対にpushしない。差分は破棄するか、クローンごと削除する（7-3-a）'
            if ($text -match 'リポジトリがまだ無い') { return $null }
            if ($text -match '結果: 追跡ファイルの変更なし・未pushなし') {
                Write-Mark 'OK' '追跡ファイルの変更も未pushのコミットも無い'
                if ($text -notmatch '未追跡ファイル[\s\S]*?（なし）') {
                    Write-Host '        未追跡ファイル（docs・生成物など）はクローンごと消す（7-3-a）' -ForegroundColor DarkGray
                }
                return 'OK'
            }
            if ($text -match '結果: 追跡ファイルの変更または未pushのコミットがある') {
                Write-Mark 'NG' '追跡ファイルに変更、または未pushのコミットがある。破棄するかクローンごと消す'
                return 'NG'
            }
            return $null
        }

    New-Step -Id '7-2-a' -Ch '7' -Title '認証情報のログアウト（手動）' -Kind manual `
        -Show @"
  1. claudeの対話中に /logout
     設定ごと消す場合: Remove-Item -Recurse -Force "`$env:USERPROFILE\.claude"
  2. VS CodeのClaude Codeパネルからサインアウト
  3. ブラウザで claude.ai からログアウト（必要ならプロファイルを削除）
"@ `
        -Expect '3つすべてでサインアウトが完了し、リハーサルで使ったアカウントが残らないこと'

    New-Step -Id '7-2-b' -Ch '7' -Title '環境変数を開始時点に戻す' -Kind change `
        -Purpose 'setxでは消せない。このリハーサルで足した分だけを戻す。実行ポリシーの変化も確かめる' `
        -Expect '開始時点から変わった変数だけが元の値に戻り、元からあった値はそのまま残る' `
        -Show @"
  起動時のUser環境変数を控えてあるので、それと比べて変わっているものだけを
  元へ戻す。元から設定されていた値は消さない。

  対象: HTTP_PROXY / HTTPS_PROXY / NO_PROXY / PIP_CERT / NODE_EXTRA_CA_CERTS

  変数ごとに「変更なし」「戻した」「削除した」を表示する。
  値そのものは表示しない（記録に客先のネットワーク情報を残さないため）。

  User PATH は戻さない。リハーサル中にインストーラが正しく足した分まで消してしまうため、
  増えた項目を報告するだけにする（消すかは人が判断する）。
"@ `
        -Cmd {
            $changed = 0
            foreach ($n in $script:EnvNames) {
                $now = [Environment]::GetEnvironmentVariable($n, 'User')
                $was = $script:EnvSnapshot[$n]
                if ($now -eq $was) {
                    if ($was) { "変更なし: $n（元から設定されていた。その値のまま残す）" }
                    else { "変更なし: $n（起動時から未設定）" }
                    continue
                }
                [Environment]::SetEnvironmentVariable($n, $was, 'User')
                $changed++
                if ($was) { "戻した  : $n（起動時の値に書き戻した）" }
                else { "削除した: $n（起動時は未設定だった）" }
            }
            if ($changed -eq 0) { 'このリハーサルでは環境変数を変えていない' }
            ''
            # 手で足したPATH（4-3-02 の対処など）は上の5つに入らないため残る。自動では消さない。
            $nowPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
            $wasItems = @($script:UserPathSnapshot -split ';')
            $added = @(($nowPath -split ';') | Where-Object { $_ } | Where-Object { $wasItems -notcontains $_ })
            if ($added.Count -gt 0) {
                "User PATH に増えた項目が $($added.Count) 件ある（自動では消さない）:"
                $added | ForEach-Object { "  $_" }
                '  → 機材に残していいものかを判断し、必要なら手で削除する'
            } else {
                'User PATH は起動時から変わっていない'
            }
            ''
            '※ 4-3-07 がこのプロセスのPATHとVIRTUAL_ENVを書き換えているが、これは'
            '   プロセス内だけの変更で、ターミナルを閉じれば消える（機材には残らない）。'
            ''
            $pol = try { (Get-ExecutionPolicy -Scope CurrentUser -ErrorAction Stop).ToString() } catch { '(取得できない)' }
            if ($pol -eq $script:PolicySnapshot) {
                "実行ポリシー(CurrentUser): $pol（起動時と同じ。変えていない）"
            } else {
                "実行ポリシー(CurrentUser): $($script:PolicySnapshot) → ${pol}に変わっている"
                "  → Set-ExecutionPolicy -ExecutionPolicy $($script:PolicySnapshot) -Scope CurrentUser で戻す"
            }
        }

    New-Step -Id '7-3-b' -Ch '7' -Title '記録の受け渡し' -Kind info `
        -Purpose '記録票と許可申請の根拠になる。機材から消す前に講師へ渡す' `
        -Show '実行時に保存先を表示する'

    # 7-3-a は 7-3-b の後ろに置く。消す前に何を渡すかを見せるため、事前確認書 7-3 の
    # 並び（受け渡し → Stop-Transcript → 削除）に合わせている。
    New-Step -Id '7-3-a' -Ch '7' -Title '作業物を消す' -Kind change `
        -Purpose '記録の受け渡し（7-3-b）が済んでから実行する' `
        -Expect 'cloneしたフォルダと証明書ファイルが消える' `
        -Show @"
  Remove-Item -Recurse -Force <cloneしたEShopのパス>
  Remove-Item "`$env:USERPROFILE\corp-ca.pem" -ErrorAction SilentlyContinue
"@ `
        -Cmd {
            if (Test-Path $script:RepoDir) {
                Remove-Item -Recurse -Force $script:RepoDir
                "削除した: $($script:RepoDir)"
            } else { "存在しない: $($script:RepoDir)" }
            Remove-Item "$env:USERPROFILE\corp-ca.pem" -ErrorAction SilentlyContinue
            "corp-ca.pem: $(if (Test-Path "$env:USERPROFILE\corp-ca.pem") { '残っている' } else { '無い' })"
        }
}

# ---------------------------------------------------------------- 実行

function Get-KindLabel([string]$Kind) {
    switch ($Kind) {
        'auto'   { '読み取り / 実行' }
        'change' { '設定変更' }
        'manual' { '手動操作' }
        'ask'    { '聞き取り' }
        'info'   { '確認のみ' }
        default  { $Kind }
    }
}

function Show-Step($Step, [int]$Index, [int]$Total) {
    $kindLabel = '<' + (Get-KindLabel $Step.Kind) + '>'
    $color = if ($Step.Kind -eq 'change') { 'Red' } else { 'Cyan' }
    Write-Host ''
    Write-Rule '='
    Write-Host (" [{0}/{1}]  {2}章 {3}  {4}" -f $Index, $Total, $Step.Ch, $Step.Id, $Step.Title) -ForegroundColor $color -NoNewline
    Write-Host ("  {0}" -f $kindLabel) -ForegroundColor DarkGray
    Write-Rule '='
    Write-Label '目的' $Step.Purpose
    Write-Label '期待' $Step.Expect 'White'
    Write-Label '聞く' $Step.Ask 'White'
    $show = Get-ShowText $Step
    if ($show) {
        Write-Host '  コマンド・操作' -ForegroundColor DarkGray
        foreach ($line in ($show -split "`n")) {
            Write-Host ('    ' + $line) -ForegroundColor Yellow
        }
    }
}

function Invoke-Step($Step) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $raw = $null
    Write-Rule
    try {
        & $Step.Cmd 2>&1 | Tee-Object -Variable raw | Out-Host
    } catch {
        Write-Host "  例外: $($_.Exception.Message)" -ForegroundColor Red
        $raw = @("例外: $($_.Exception.Message)")
    }
    $sw.Stop()
    Write-Rule
    $sec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Write-Host ("  所要 {0}秒" -f $sec) -ForegroundColor DarkGray
    if ($Step.TimeKey) { $script:Timings[$Step.TimeKey] = $sec }
    # 記録に残すのは伏せ字を当てたもの、判定は当てる前のもので行う。
    # 伏せ字の対象と形が重なる値（4つドット区切りの版番号など）が潰れて、判定が
    # 壊れるのを根元で防ぐ。Hint が出すのは件数や空き容量などの抽出値だけなので、
    # 当てる前を渡しても画面や記録に客先の情報は出ない。
    $clean = Remove-AnsiEscape ($raw | Out-String -Width 200)
    $text = Hide-NetworkInfo $clean
    $script:Captured[$Step.Id] = $text
    $suggest = $null
    if ($Step.Hint) {
        try { $suggest = & $Step.Hint $clean } catch { }
    }
    if ($suggest) { $suggest = ("$suggest").Trim() }
    if ($suggest -and $suggest -notin 'OK', 'NG', '保留', '注意', '参考', '未確認') { $suggest = $null }
    return @{ Text = $text; Seconds = $sec; Suggest = $suggest }
}

function Set-AutoVerdict($Step, $Result) {
    if ($Result.Suggest) {
        $verdict = $Result.Suggest
        $memo = '自動判定'
    } else {
        $verdict = '自動'
        $memo = '判定の根拠が無いステップ。出力を見て講師が判断する'
    }
    Write-Host ("  {0}  として記録" -f (Get-MarkLabel $verdict)) -ForegroundColor (Get-MarkColor $verdict)
    Add-Result $Step $verdict $Result.Text $memo $Result.Seconds
}

function Read-Verdict($Step, [string]$Output, [double]$Seconds, [string]$Suggest) {
    $memo = ''
    # 目安があるならそれを Enter の既定にする。「目安: NG」と出した直後に Enter が OK に
    # なると、惰性で押したときに誤って記録される。Enter のラベルが目安を兼ねるので、
    # 「判定の目安: NG」の行は別に出さない（同じことを2度言わない）。
    $default = if ($Suggest) { $Suggest } else { 'OK' }
    # 既定と同じキーは出さない。出すと同じ判定にキーが2つ並んで、違いが画面に出ない
    $keys = @('[Enter]={0}{1}' -f $default, $(if ($Suggest) { '（目安どおり）' } else { '' }))
    if ($default -ne 'OK') { $keys += '[o]=OK' }
    if ($default -ne 'NG') { $keys += '[n]=NG' }
    if ($default -ne '保留') { $keys += '[h]=保留' }
    $keys += '[m]=メモを書く'
    $keys += '[q]=保留にして中断'
    $prompt = '判定  ' + ($keys -join '   ')
    while ($true) {
        $ans = Read-Key $prompt
        $v = switch ($ans.ToLower()) {
            ''  { $default }
            'o' { 'OK' }
            'n' { 'NG' }
            'h' { '保留' }
            default { $null }
        }
        if ($v) {
            Add-Result $Step $v $Output $memo $Seconds
            Write-Host ("  {0}  として記録" -f (Get-MarkLabel $v)) -ForegroundColor (Get-MarkColor $v)
            return
        }
        if ($ans.ToLower() -eq 'm') { $memo = Read-Host '  メモ'; continue }
        if ($ans.ToLower() -eq 'q') {
            Add-Result $Step '保留' $Output $memo $Seconds
            $script:Aborted = $true
            Write-Host '  保留として記録し、中断する' -ForegroundColor Yellow
            return
        }
        Write-Host '  Enter / o / n / h / m / q のいずれかを入力する' -ForegroundColor DarkGray
    }
}

function Show-Timings {
    $rows = @(
        @{ Key = 'install';     Label = 'Claude Codeのインストール';      Ref = '' }
        @{ Key = 'clone';       Label = 'git clone';                     Ref = '社内1.2秒' }
        @{ Key = 'venv';        Label = 'python -m venv';                Ref = '社内8.5秒' }
        @{ Key = 'pip';         Label = 'pip install -r requirements';   Ref = '社内31.4秒' }
        @{ Key = 'seed';        Label = 'python -m app.seed（main）';     Ref = '社内1.9秒' }
        @{ Key = 'pytest-main'; Label = 'pytest（54件）';                 Ref = '社内8.6秒' }
        @{ Key = 'fetch';       Label = 'git fetch + switch coupon';        Ref = '' }
        @{ Key = 'seed-no3';    Label = 'DB削除 + seed（coupon）';           Ref = '' }
        @{ Key = 'pytest-no3';  Label = 'pytest（55件）';                 Ref = '' }
    )
    Write-Host ''
    Write-Host '  6-1 No.1のセットアップ（ハンズオン持ち時間の目安12分）' -ForegroundColor Cyan
    $no1 = 0.0
    foreach ($r in $rows[0..5]) {
        $v = $script:Timings[$r.Key]
        if ($null -ne $v) { $no1 += [double]$v }
        Write-Host ('    {0,-34} {1,8}  {2}' -f $r.Label, $(if ($null -ne $v) { "${v}秒" } else { '未計測' }), $r.Ref)
    }
    Write-Host ('    {0,-34} {1,8}' -f '小計', "$([math]::Round($no1,1))秒") -ForegroundColor White
    Write-Host ''
    Write-Host '  6-2 No.3の導入（20分枠）' -ForegroundColor Cyan
    $no3 = 0.0
    foreach ($r in $rows[6..8]) {
        $v = $script:Timings[$r.Key]
        if ($null -ne $v) { $no3 += [double]$v }
        Write-Host ('    {0,-34} {1,8}  {2}' -f $r.Label, $(if ($null -ne $v) { "${v}秒" } else { '未計測' }), $r.Ref)
    }
    Write-Host ('    {0,-34} {1,8}' -f '小計', "$([math]::Round($no3,1))秒") -ForegroundColor White
    Write-Host ''
    # 担当者ではなく講師への指示。6章の所要時間が埋まるかに直結するので、飛ばせない
    Write-Host '  claude.aiへのログインとVS Code拡張の導入は手動操作のため、時計で測って記録票に書く' -ForegroundColor Cyan
}

function Save-Record {
    $path = $script:RecordPath
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("# 事前確認書 第I部 実施記録")
    $null = $sb.AppendLine()
    $null = $sb.AppendLine("- 実施日時: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    $null = $sb.AppendLine("- 機材: $env:COMPUTERNAME")
    $null = $sb.AppendLine("- 実施者: $env:USERNAME")
    $null = $sb.AppendLine("- 作業フォルダ: $script:WorkRoot")
    $null = $sb.AppendLine("- 対象章: $($script:TargetChapters -join ', ')")
    # 記録が途中で終わったのか、その章が対象外だったのかを、読んだだけで分かるようにする。
    # Ctrl+Cやウィンドウを閉じた場合は Aborted が立たないので、進捗は常に出す。
    $null = $sb.AppendLine("- 進捗: 全 $($script:TotalSteps)ステップ中 $($script:Results.Count)ステップを実施")
    if ($script:Aborted) { $null = $sb.AppendLine('- **[q]で途中で中断した**') }
    $null = $sb.AppendLine("- 記録した時点: $(Get-Date -Format 'HH:mm:ss')（1ステップごとに更新される）")
    $null = $sb.AppendLine("- スクリプトの版: $script:ScriptVersion")
    $null = $sb.AppendLine("- PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))　文字コード: CP$($script:ConsoleCodePage) / PYTHONIOENCODING=$($env:PYTHONIOENCODING)")
    $null = $sb.AppendLine('- このファイルには客先のネットワーク情報を残さない。プロキシのアドレス・除外リスト・PACのURL・IPアドレスは伏せ字に置き換え、3-4-3で入力したURLは書かない')
    $null = $sb.AppendLine('- ただし画面の記録（rehearsal-check.txt）は伏せていない。入力した文字もそのまま残るため、渡す経路と削除は7-3に従う')
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('## 判定一覧')
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('| 章 | 項目 | 種別 | 判定 | 所要 | メモ |')
    $null = $sb.AppendLine('| :-- | :-- | :-- | :-- | --: | :-- |')
    foreach ($r in $script:Results) {
        $secText = if ($r.Seconds -ge 0) { "$($r.Seconds)秒" } else { '' }
        $memo = ($r.Memo -replace '\|', '\|') -replace "`r?`n", ' '
        $null = $sb.AppendLine("| $($r.Ch) | $($r.Id) $($r.Title) | $(Get-KindLabel $r.Kind) | $($r.Verdict) | $secText | $memo |")
    }
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('## 所要時間（6章）')
    $null = $sb.AppendLine()
    foreach ($k in $script:Timings.Keys | Sort-Object) {
        $null = $sb.AppendLine("- $k : $($script:Timings[$k])秒")
    }
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('## 各ステップの出力')
    foreach ($r in $script:Results) {
        $null = $sb.AppendLine()
        $null = $sb.AppendLine("### $($r.Id) $($r.Title)  [$($r.Verdict)]")
        $null = $sb.AppendLine()
        if ($r.Command) {
            $null = $sb.AppendLine('```text')
            $null = $sb.AppendLine($r.Command)
            $null = $sb.AppendLine('```')
        }
        if ($r.Output) {
            $null = $sb.AppendLine()
            $null = $sb.AppendLine('```text')
            $null = $sb.AppendLine($r.Output.TrimEnd())
            $null = $sb.AppendLine('```')
        }
        if ($r.Memo) {
            $null = $sb.AppendLine()
            $null = $sb.AppendLine("メモ: $($r.Memo)")
        }
    }
    [System.IO.File]::WriteAllText($path, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))
    return $path
}

function Save-StepList {
    param($Steps)
    $path = $script:StepListPath
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine('# 事前確認書 第I部 ステップ一覧（下見）')
    $null = $sb.AppendLine()
    $null = $sb.AppendLine("- 出力日時: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    $null = $sb.AppendLine("- 対象章: $($script:TargetChapters -join ', ')")
    $null = $sb.AppendLine("- 全 $(@($Steps).Count) ステップ")
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('| # | 章 | ID | 確認項目 | 種別 |')
    $null = $sb.AppendLine('| --: | :-- | :-- | :-- | :-- |')
    $i = 0
    foreach ($st in $Steps) {
        $i++
        $null = $sb.AppendLine("| $i | $($st.Ch) | $($st.Id) | $($st.Title) | $(Get-KindLabel $st.Kind) |")
    }
    $i = 0
    foreach ($st in $Steps) {
        $i++
        $null = $sb.AppendLine()
        $null = $sb.AppendLine("## $i. $($st.Id) $($st.Title)")
        $null = $sb.AppendLine()
        $null = $sb.AppendLine("- 章: $($st.Ch)　種別: $(Get-KindLabel $st.Kind)")
        if ($st.Purpose) { $null = $sb.AppendLine("- 目的: $($st.Purpose)") }
        if ($st.Expect) { $null = $sb.AppendLine("- 期待: $($st.Expect)") }
        if ($st.Ask) { $null = $sb.AppendLine("- 聞く: $($st.Ask)") }
        $show = Get-ShowText $st
        if ($show) {
            $null = $sb.AppendLine()
            $null = $sb.AppendLine('```text')
            $null = $sb.AppendLine($show.TrimEnd())
            $null = $sb.AppendLine('```')
        }
    }
    [System.IO.File]::WriteAllText($path, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))
    return $path
}

# ---------------------------------------------------------------- 講座当日の診断（-Diagnose）
#
# 受講者のPCで、受講者が自分の EShop を診断する。講師は画面共有で結果を見る。
# リハーサルのステップ（New-Step）とは別の一覧で、事前確認書の章立てには対応しない。
# deploy-rehearsal.py の整合検査は New-Step だけを見るので、こちらは New-Check で定義する。
#
# 受講者が作業中の環境なので、読み取りだけにする。clone・pip・seed・DBの削除・ブランチの
# 切り替え・サーバーの起動は行わない。直す操作は、表示した手順書の手順どおりに受講者が行う。
# 書き込むのは EShop の外に置く記録ファイルと、hook を試すときの一時ファイルだけ。
# pytest にはキャッシュとバイトコードを書かせない。
#
# .env の値は画面共有に映るため表示しない（キー名と形だけを見る）。
# プロキシまわりは -Network を付けたときだけ見る（既定では設定を読みにも行かない）。

$script:Checks = @()
$script:DxResults = @()
$script:DxFix = @()
$script:Dx = @{}

function New-Check {
    param([string]$Id, [string]$Group, [string]$Title, [string]$Ref, [scriptblock]$Cmd, [scriptblock]$Hint)
    # Invoke-Step にそのまま渡せる形にする（Id・Cmd・Hint・TimeKey を見る）
    $script:Checks += [pscustomobject]@{
        Id = $Id; Group = $Group; Title = $Title; Ref = $Ref
        Cmd = $Cmd; Hint = $Hint; TimeKey = $null
    }
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

function Invoke-DxGit {
    # git はパスを UTF-8 で出す。PowerShell 5.1 はネイティブの出力を CP932 として読むため、
    # docs\要件整理メモ.md のような日本語のファイル名が化ける。この間だけ UTF-8 で読む。
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

function Invoke-DxPython([string]$Python, [string]$Code, [string[]]$Arguments) {
    # コードは ASCII だけで書く。PowerShell 5.1 はネイティブへ渡す標準入力を ASCII で書くため、
    # 日本語を混ぜると化ける。引数（パス）はコマンドラインで渡るので日本語でもよい。
    $Code | & $Python - @Arguments 2>&1 | ForEach-Object { "$_" }
}

function Find-GitBash {
    # Windows の Claude Code は hook のコマンドを Git Bash で実行する
    # （03-05 の解答例は "$CLAUDE_PROJECT_DIR/..." と bash の書き方で動いている）
    $cands = @()
    if ($env:CLAUDE_CODE_GIT_BASH_PATH) { $cands += $env:CLAUDE_CODE_GIT_BASH_PATH }
    $g = (Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if ($g) {
        # ...\Git\cmd\git.exe・...\Git\mingw64\bin\git.exe のどちらからでも ...\Git\bin\bash.exe に届く
        $root = $g
        for ($i = 0; $i -lt 3; $i++) {
            $root = Split-Path $root -Parent
            if (-not $root) { break }
            $cands += Join-Path $root 'bin\bash.exe'
        }
    }
    if ($env:ProgramFiles) { $cands += Join-Path $env:ProgramFiles 'Git\bin\bash.exe' }
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

function Invoke-DxHook([string]$Bash, [string]$Command, [string]$Json) {
    # Claude Code と同じく、標準入力に JSON を渡して hook のコマンドを1回呼ぶ。ツール自体は
    # 実行しないので、hook が止めても通してもファイルは変わらない。
    # 固まる hook に備えて待ち時間を切る。コマンドの引用符を崩さないよう、一時ファイルに書いて渡す。
    $sh = Join-Path $env:TEMP "eshop-diagnose-hook-$PID.sh"
    [System.IO.File]::WriteAllText($sh, $Command + "`n", (New-Object System.Text.UTF8Encoding $false))
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Bash
        $psi.Arguments = '"' + $sh + '"'
        $psi.WorkingDirectory = $script:Dx.Repo
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $psi.EnvironmentVariables['CLAUDE_PROJECT_DIR'] = ($script:Dx.Repo -replace '\\', '/')
        # このスクリプトは PYTHONIOENCODING をコンソールに合わせている（CP932 のことがある）。
        # hook の標準エラーは UTF-8 で読むので、Python の hook にも UTF-8 で書かせる
        $psi.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
        $p = [System.Diagnostics.Process]::Start($psi)
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
        try { $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length); $p.StandardInput.Close() } catch { }
        if ($p.WaitForExit(20000)) {
            $p.WaitForExit()
            $code = "$($p.ExitCode)"
        } else {
            try { $p.Kill() } catch { }
            $code = 'タイムアウト（20秒）'
        }
        return @{ Code = $code; Out = $outTask.Result; Err = $errTask.Result }
    } catch {
        return @{ Code = "起動できない: $($_.Exception.Message)"; Out = ''; Err = '' }
    } finally {
        Remove-Item $sh -Force -ErrorAction SilentlyContinue
    }
}

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
            # 使えないことがある。同じ値をレジストリから読む（2-1-c と同じ）
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

    New-Check -Id 'D2-2' -Group 'リポジトリ' -Title 'ブランチと作業の状態' -Ref '03-01 手順0' -Cmd {
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
        $docs = @(Get-ChildItem (Join-Path $script:Dx.Repo 'docs') -Filter *.md -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        "docs       => $(if ($docs.Count -gt 0) { $docs -join ', ' } else { '無い' })"
        # 基本設計書.md は配布時から入っていて、No.2 で受講者が追記する。main と coupon で同じ内容なので、
        # 配布された状態との差がそのまま受講者の追記になる
        $api = Join-Path $script:Dx.Repo 'docs\基本設計書.md'
        $apiState = if (-not (Test-Path $api)) { '無い' }
                    else {
                        $null = @(Invoke-DxGit diff --quiet $script:Dx.Base '--' docs/基本設計書.md)
                        if ($LASTEXITCODE -eq 1) { '追記あり' } else { '配布時のまま' }
                    }
        "基本設計書.md => $apiState"
        "coupon.py  => $(if (Test-Path (Join-Path $script:Dx.Src 'app\coupon.py')) { 'あり' } else { 'なし' })"
        $oc = @(Invoke-DxGit rev-parse --verify --quiet origin/coupon)
        "origin/coupon => $(if ($LASTEXITCODE -eq 0 -and $oc.Count -gt 0) { '取得済み' } else { 'まだ無い（git fetch origin で取得する）' })"
    } -Hint {
        param($text)
        $br = $script:Dx.Branch
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
        $r = 'OK'
        switch ($br) {
            'main' {
                Write-Mark '参考' 'main ブランチ（No.1・No.2 の状態）'
                if ($app.Count -gt 0 -or $tests.Count -gt 0) {
                    Write-Mark '注意' '配布されたコード（backend/app・backend/tests）が変わっている'
                    Write-Fix 'No.1・No.2 ではコードを変えない。No.3 で pytest が失敗する原因になるので、講師と一緒に上の一覧を確かめる'
                    $r = '注意'
                }
            }
            'coupon' {
                Write-Mark '参考' 'coupon ブランチ（No.3 以降の状態）'
                if ($text -match 'coupon\.py  => なし') {
                    Write-Mark 'NG' 'coupon ブランチなのに app\coupon.py が無い'
                    Write-Fix '講師に申し出る（03-01 手順0 の切り替えが途中で止まっている可能性がある）'
                    return 'NG'
                }
                if ($text -notmatch 'docs       => .*要件整理メモ\.md') {
                    Write-Mark '注意' 'No.2 で作った要件整理メモ（docs\要件整理メモ.md）が無い'
                    Write-Fix '03-01 前提条件: No.2 の要件整理メモを EShop\docs に置く'
                    $r = '注意'
                }
                if ($text -match '基本設計書\.md => 配布時のまま') {
                    Write-Mark '注意' 'docs\基本設計書.md にクーポン機能が追記されていない'
                    Write-Fix '02-02 手順6: No.2 で決めたクーポン機能の設計を docs\基本設計書.md に追記する'
                    $r = '注意'
                }
                if ($tests.Count -gt 0) {
                    Write-Mark '注意' '配布された既存のテストが書き換えられている'
                    Write-Fix '03-02 手順2: backend で git restore tests/<ファイル名> で戻し、hook で止まるかを確かめる'
                    $r = '注意'
                }
                if ($app.Count -gt 0) {
                    Write-Mark '参考' 'backend/app を変えている（03-03 のデバッグや No.4 の実装で直した分なら問題ない）'
                }
            }
            default {
                Write-Mark '注意' "手順書に無いブランチ（$br）にいる"
                Write-Fix 'No.1・No.2 は main、No.3 以降は coupon を使う。切り替える前に講師に申し出る'
                $r = '注意'
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

    New-Check -Id 'D4-1' -Group 'データベース' -Title '初期データ（backend\ecommerce.db）' -Ref '01-01 手順3・03-01 手順0-2' -Cmd {
        $py = Get-DxPython
        if (-not $py) { $py = (Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
        if (-not $py) { 'python が無いため確認しない'; return }
        # 読み取り専用で開く（mode=ro）。サーバーが起動中でも中身を変えない
        $code = @'
import os, pathlib, sqlite3, sys
p = sys.argv[1]
if not os.path.exists(p):
    print("db: missing")
    sys.exit(0)
print("db: exists (%d bytes)" % os.path.getsize(p))
try:
    con = sqlite3.connect(pathlib.Path(p).resolve().as_uri() + "?mode=ro", uri=True)
    names = sorted(r[0] for r in con.execute("select name from sqlite_master where type='table'"))
    print("tables: " + ", ".join(names))
    for t in ("users", "products", "coupons", "orders"):
        if t in names:
            print("count %s: %d" % (t, con.execute('select count(*) from "%s"' % t).fetchone()[0]))
    if "orders" in names:
        print("orders columns: " + ", ".join(r[1] for r in con.execute("pragma table_info(orders)")))
except Exception as e:
    print("error: %s" % e)
'@
        Invoke-DxPython $py $code @((Join-Path $script:Dx.Src 'ecommerce.db'))
        "EShop直下の ecommerce.db => $(if (Test-Path (Join-Path $script:Dx.Repo 'ecommerce.db')) { 'あり' } else { 'なし' })"
    } -Hint {
        param($text)
        $seed = if ($script:Dx.Branch -eq 'coupon') { '03-01 手順0-2' } else { '01-01 手順3' }
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
        if ($script:Dx.Branch -eq 'coupon' -and ($text -notmatch 'orders columns: .*coupon_code' -or $text -notmatch 'tables: .*coupons')) {
            Write-Mark 'NG' 'No.1 で作った DB のまま。注文確定で table orders has no column named coupon_code になる'
            Write-Fix '03-01 手順0-2: サーバーを止めて、backend で Remove-Item ecommerce.db のあと python -m app.seed'
            return 'NG'
        }
        $u = if ($text -match 'count users: (\d+)') { [int]$Matches[1] } else { 0 }
        $p = if ($text -match 'count products: (\d+)') { [int]$Matches[1] } else { 0 }
        if ($u -lt 2 -or $p -lt 5) {
            Write-Mark '注意' "初期データが足りない（ユーザー${u}件・商品${p}件。seed はユーザー2件・商品5件）"
            Write-Fix "${seed}: サーバーを止めて、backend で Remove-Item ecommerce.db のあと python -m app.seed"
            return '注意'
        }
        if ($script:Dx.Branch -eq 'main' -and $text -match 'tables: .*coupons') {
            Write-Mark '参考' 'coupon ブランチで作った DB（main で使っても動く）'
        }
        Write-Mark 'OK' '初期データが入っている'
        return 'OK'
    }

    # ====================== サーバー ======================

    New-Check -Id 'D5-1' -Group 'サーバー' -Title '8000番とSwagger UI' -Ref '01-01 手順4' -Cmd {
        # サーバーは起動しない。起動中なら応答を見る（プロキシを通さずに 127.0.0.1 へ直接）
        $pids = @()
        $conns = @(Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue)
        if ($conns.Count -gt 0) {
            $pids = @($conns | ForEach-Object { $_.OwningProcess } | Sort-Object -Unique)
        } else {
            # Get-NetTCPConnection が無い機材に備えて、待ち受けられるかで確かめる
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
            Write-Host '        起動するときは 01-01 手順4: backend で uvicorn app.main:app --reload' -ForegroundColor DarkGray
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
        New-Check -Id 'D6-1' -Group 'テスト' -Title '配布されたテスト（pytest）' -Ref '01-01 手順5・03-01 手順0-2' -Cmd {
            $py = Get-DxPython
            if (-not $py) { '仮想環境が無いため実行しない'; return }
            # 実行するのは配布されたテストだけ。自分で作ったテスト（03-02 の test_coupon.py など）は
            # 演習の途中では失敗してよいので、ここでは数えない
            $dist = @(Invoke-DxGit ls-tree -r --name-only $script:Dx.Base '--' backend/tests |
                Where-Object { $_ -match '^backend/tests/test_[^/]*\.py$' })
            $here = @(Get-ChildItem (Join-Path $script:Dx.Src 'tests') -Filter 'test_*.py' -ErrorAction SilentlyContinue |
                ForEach-Object { "backend/tests/$($_.Name)" })
            $mine = @($here | Where-Object { $dist -notcontains $_ })
            $gone = @($dist | Where-Object { $here -notcontains $_ })
            $mod = @(Invoke-DxGit diff --name-only --diff-filter=M $script:Dx.Base '--' backend/tests | Where-Object { $_ })
            "配布されたテスト   => $($dist.Count)ファイル（これだけを実行する）"
            "自分で作ったテスト => $(if ($mine.Count -gt 0) { $mine -join ', ' } else { 'なし' })（実行しない）"
            "書き換えた既存テスト => $(if ($mod.Count -gt 0) { $mod -join ', ' } else { 'なし' })"
            if ($gone.Count -gt 0) { "消えた既存テスト   => $($gone -join ', ')" }
            ''
            $rel = @($dist | Where-Object { $here -contains $_ } | ForEach-Object { $_ -replace '^backend/', '' })
            if ($rel.Count -eq 0) { '実行できるテストが無い'; return }
            $prevB = $env:PYTHONDONTWRITEBYTECODE
            $env:PYTHONDONTWRITEBYTECODE = '1'
            Push-Location $script:Dx.Src
            try {
                & $py -m pytest -q -p no:cacheprovider --disable-warnings --tb=line -rfE @rel 2>&1 | ForEach-Object { "$_" }
            } finally {
                Pop-Location
                $env:PYTHONDONTWRITEBYTECODE = $prevB
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
                if ($script:Dx.Branch -eq 'coupon') {
                    Write-Fix '03-03 や No.4 でコードを直したあとなら、その修正が既存の機能を壊している（回帰）。D2-2 の一覧のファイルを git diff で見直す'
                    Write-Fix '直す前から失敗するなら、03-01 手順0（切り替え）と手順0-2（DBの作り直し）を確かめる'
                } else {
                    Write-Fix 'D2-3（.env）と D3-3（依存パッケージ）を先に見る。どちらも OK なら講師に申し出る'
                }
                return 'NG'
            }
            $expect = switch ($script:Dx.Branch) { 'main' { 54 } 'coupon' { 55 } default { 0 } }
            if ($expect -gt 0 -and $passed -ne $expect) {
                Write-Mark '注意' "すべて PASS だが、件数が基準（${expect}件）と違う（${passed}件）"
                if ($text -match '書き換えた既存テスト => (?!なし)' -or $text -match '消えた既存テスト') {
                    Write-Fix '03-02 手順2: 書き換えた・消した既存テストを backend で git restore tests/<ファイル名> で戻す'
                } else {
                    Write-Fix '講師に申し出る（ブランチの状態を一緒に確かめる）'
                }
                return '注意'
            }
            Write-Mark 'OK' "${passed}件すべて PASS$(if ($expect -gt 0) { '（基準どおり）' })"
            return 'OK'
        }
    }

    # ====================== Claude Code の設定 ======================

    New-Check -Id 'D7-1' -Group 'Claude Codeの設定' -Title 'CLAUDE.md' -Ref '01-03 手順2' -Cmd {
        $f = Join-Path $script:Dx.Repo 'CLAUDE.md'
        if (Test-Path $f) { "EShop直下の CLAUDE.md => あり（$(@(Get-Content -LiteralPath $f -Encoding UTF8).Count)行）" }
        else { 'EShop直下の CLAUDE.md => 無い' }
        if (Test-Path (Join-Path $script:Dx.Src 'CLAUDE.md')) { 'backendの CLAUDE.md => あり' }
    } -Hint {
        param($text)
        if ($text -match '直下の CLAUDE\.md => あり') { Write-Mark 'OK' 'EShop 直下にある'; return 'OK' }
        if ($text -match 'backendの CLAUDE\.md => あり') {
            Write-Mark '注意' 'backend の中に作っている。EShop 直下に置く'
            Write-Fix '01-03 手順2: CLAUDE.md を EShop 直下へ移し、Claude Code を開き直す'
            return '注意'
        }
        if ($script:Dx.Branch -eq 'coupon') {
            Write-Mark '注意' 'No.1（01-03）で作った CLAUDE.md が無い'
            Write-Fix '01-03 手順2: EShop 直下に CLAUDE.md を作る'
            return '注意'
        }
        Write-Mark '参考' 'まだ無い（01-03 手順2 で EShop 直下に作る）'
        return '参考'
    }

    New-Check -Id 'D7-2' -Group 'Claude Codeの設定' -Title '設定ファイル（settings.json）' -Ref '03-02 手順2' -Cmd {
        $script:Dx.Hooks = @()
        $files = @(
            @{ Label = 'EShop\.claude\settings.json';       Path = (Join-Path $script:Dx.Repo '.claude\settings.json');       Hooks = $true }
            @{ Label = 'EShop\.claude\settings.local.json'; Path = (Join-Path $script:Dx.Repo '.claude\settings.local.json'); Hooks = $false }
            @{ Label = '利用者の settings.json';            Path = (Join-Path $env:USERPROFILE '.claude\settings.json');      Hooks = $false }
        )
        foreach ($f in $files) {
            if (-not (Test-Path -LiteralPath $f.Path)) { "$($f.Label) => 無い"; continue }
            $raw = Get-Content -LiteralPath $f.Path -Raw -Encoding UTF8
            if (-not "$raw".Trim()) { "$($f.Label) => 空のファイル（JSONとして読めない）"; continue }
            try { $j = $raw | ConvertFrom-Json -ErrorAction Stop }
            catch {
                # 利用者の設定は中身に触れない。講座の設定だけ、誤りの位置を出す
                if ($f.Hooks) { "$($f.Label) => JSONの書式が壊れている: $($_.Exception.Message)" }
                else { "$($f.Label) => JSONの書式が壊れている" }
                continue
            }
            "$($f.Label) => JSONとして読める"
            if ($f.Hooks -and $j.hooks) {
                foreach ($ev in $j.hooks.PSObject.Properties) {
                    foreach ($m in @($ev.Value)) {
                        foreach ($h in @($m.hooks)) {
                            "  hook: $($ev.Name)  matcher=$($m.matcher)"
                            "        $($h.command)"
                            $script:Dx.Hooks += [pscustomobject]@{ Event = $ev.Name; Matcher = "$($m.matcher)"; Command = "$($h.command)" }
                        }
                    }
                }
            }
        }
    } -Hint {
        param($text)
        if ($text -match '(?m)^(.+) => (JSONの書式が壊れている|空のファイル)') {
            Write-Mark 'NG' "$($Matches[1]) を Claude Code が読めない（JSON の書式の誤り）"
            Write-Fix '上の誤りの位置をAIに見せて直させるか、講師に申し出る。直したら Developer: Reload Window で開き直す'
            return 'NG'
        }
        if ($text -match 'hook: ') { Write-Mark 'OK' 'JSON として読めて、hook が設定されている'; return 'OK' }
        if ($script:Dx.Branch -eq 'coupon') {
            Write-Mark '参考' 'hook はまだ無い（03-02 手順2 で作る）'
            return '参考'
        }
        Write-Mark 'OK' '読めない設定ファイルは無い'
        return 'OK'
    }

    New-Check -Id 'D7-3' -Group 'Claude Codeの設定' -Title 'hook で既存テストが守られるか（試しに呼ぶ）' -Ref '03-02 手順2' -Cmd {
        $hooks = @($script:Dx.Hooks | Where-Object { $_.Event -eq 'PreToolUse' })
        if ($hooks.Count -eq 0) { 'PreToolUse の hook => 無い'; return }
        $bash = Find-GitBash
        if (-not $bash) { 'Git Bash が見つからないため試せない'; return }
        "Git Bash => $bash"
        $orders = Join-Path $script:Dx.Src 'tests\test_orders.py'
        $probe = Join-Path $script:Dx.Src 'tests\test_diagnose_probe.py'
        foreach ($h in $hooks) {
            ''
            "hook: $($h.Command)"
            $mt = if ($h.Matcher) { $h.Matcher } else { '.*' }
            if ($mt -eq '*') { $mt = '.*' }
            $mE = try { 'Edit' -match "^(?:$mt)$" } catch { $false }
            $mW = try { 'Write' -match "^(?:$mt)$" } catch { $false }
            "  対象のツール => Edit: $(if ($mE) { '対象' } else { '対象外' })  Write: $(if ($mW) { '対象' } else { '対象外' })"
            if ($mE) {
                $json = @{ session_id = 'eshop-diagnose'; hook_event_name = 'PreToolUse'; cwd = $script:Dx.Repo; tool_name = 'Edit'
                    tool_input = @{ file_path = $orders; old_string = 'x'; new_string = 'y' } } | ConvertTo-Json -Compress -Depth 5
                $r = Invoke-DxHook $bash $h.Command $json
                "  既存のテスト（tests\test_orders.py）への Edit => 終了コード $($r.Code)"
                foreach ($l in (("$($r.Err)".Trim()) -split "`r?`n")) { if ($l) { "      $l" } }
            }
            if ($mW) {
                $json = @{ session_id = 'eshop-diagnose'; hook_event_name = 'PreToolUse'; cwd = $script:Dx.Repo; tool_name = 'Write'
                    tool_input = @{ file_path = $probe; content = '' } } | ConvertTo-Json -Compress -Depth 5
                $r = Invoke-DxHook $bash $h.Command $json
                "  新しいテスト（tests\test_diagnose_probe.py）への Write => 終了コード $($r.Code)"
                foreach ($l in (("$($r.Err)".Trim()) -split "`r?`n")) { if ($l) { "      $l" } }
            }
        }
    } -Hint {
        param($text)
        if ($text -match 'hook => 無い') {
            Write-Mark '参考' 'hook は No.3 の 03-02 手順2 で作る（まだなら問題ない）'
            return '参考'
        }
        if ($text -match 'Git Bash が見つからない') { Write-Mark '未確認' 'Git Bash が見つからないため試せない'; return '未確認' }
        if ($text -notmatch 'Edit: 対象') {
            Write-Mark '注意' 'hook の matcher が Edit を対象にしていない'
            Write-Fix '03-02 手順2 の「確かめること」: matcher が Edit|Write になっているかを見て、AIに直させる'
            return '注意'
        }
        if ($text -match 'Edit => 終了コード 2') {
            if ($text -match 'Write => 終了コード 2') {
                Write-Mark '注意' '既存のテストは止まるが、新しいテストファイルも止めてしまう'
                Write-Fix '03-02 手順2 の「止めないこと」（git が追跡していないファイル）を満たすよう、AIに直させる'
                return '注意'
            }
            if ($text -notmatch 'Write: 対象') {
                Write-Mark '注意' '既存のテストへの Edit は止まるが、Write は対象外（書き換えの一部が素通りする）'
                Write-Fix '03-02 手順2 の「確かめること」: matcher を Edit|Write にするようAIに直させる'
                return '注意'
            }
            Write-Mark 'OK' '既存のテストへの書き込みは止まり、新しいテストファイルは書ける'
            return 'OK'
        }
        if ($text -match 'Edit => 終了コード 1\b') {
            Write-Mark 'NG' 'hook のスクリプトがエラーで落ちている（終了コード1）。止めずに素通りする'
            Write-Fix '03-02 手順2: 上に出たエラーをAIに見せてスクリプトを直させ、Developer: Reload Window のあと止まるかを試す'
            return 'NG'
        }
        if ($text -match 'Edit => 終了コード 0\b') {
            Write-Mark 'NG' '既存のテストへの書き込みを止めていない（終了コード0）'
            Write-Fix '03-02 手順2: git ls-files で追跡の有無を見ているか、止めるときに sys.exit(2) で終えているかをAIに確かめさせる'
            return 'NG'
        }
        Write-Mark 'NG' 'hook のコマンドを実行できない（パスの誤りなど）'
        Write-Fix '03-02 手順2: settings.json の command に書いたパスが実在するかを確かめ、AIに直させる'
        return 'NG'
    }
}

function Initialize-Redaction {
    # 記録から伏せるネットワーク情報を集める（プロキシのアドレス・除外リスト・PACのURL）
    $script:Redactions = @()
    foreach ($n in 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY') {
        Add-Redaction ([Environment]::GetEnvironmentVariable($n)) '<プロキシ>'
        Add-Redaction ([Environment]::GetEnvironmentVariable($n, 'User')) '<プロキシ>'
        Add-Redaction ([Environment]::GetEnvironmentVariable($n, 'Machine')) '<プロキシ>'
    }
    Add-Redaction ([Environment]::GetEnvironmentVariable('NO_PROXY')) '<除外>'
    Add-Redaction ([Environment]::GetEnvironmentVariable('NO_PROXY', 'User')) '<除外>'
    try {
        $ri = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        Add-Redaction $ri.ProxyServer '<プロキシ>'
        Add-Redaction $ri.AutoConfigURL '<PACのURL>'
        Add-Redaction $ri.ProxyOverride '<除外>'
    } catch { }
    try {
        $sp = [System.Net.WebRequest]::GetSystemWebProxy()
        foreach ($h in 'https://api.anthropic.com', 'https://pypi.org', 'https://github.com') {
            $g = $sp.GetProxy([Uri]$h)
            if ($g -and $g.AbsoluteUri -ne ([Uri]$h).AbsoluteUri) {
                Add-Redaction $g.Authority '<プロキシ>'
                Add-Redaction $g.Host '<プロキシ>'
            }
        }
    } catch { }
}

function Save-DiagnoseRecord {
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine('# EShop 診断の記録')
    $null = $sb.AppendLine()
    $null = $sb.AppendLine("- 実施日時: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $null = $sb.AppendLine("- PC: $env:COMPUTERNAME")
    $null = $sb.AppendLine("- EShop: $($script:Dx.Repo)")
    $null = $sb.AppendLine("- ブランチ: $(if ($script:Dx.Branch) { $script:Dx.Branch } else { '（なし）' })（$($script:Dx.Stage)）")
    $null = $sb.AppendLine("- 通信の確認（-Network）: $(if ($Network) { 'した' } else { 'していない' })　pytest: $(if ($SkipTest) { '実行していない（-SkipTest）' } else { '実行した' })")
    $null = $sb.AppendLine("- スクリプトの版: $script:ScriptVersion")
    $null = $sb.AppendLine("- PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))　文字コード: CP$($script:ConsoleCodePage)")
    $null = $sb.AppendLine('- 読み取りだけの診断で、EShop のファイルは変えていない。.env の値は記録していない')
    if ($Network) { $null = $sb.AppendLine('- プロキシのアドレス・除外リスト・PACのURL・IPアドレスは伏せ字にしてある') }
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
            foreach ($f in $r.Fix) { $null = $sb.AppendLine("  - $(Hide-NetworkInfo $f)") }
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

function Invoke-Diagnose {
    Write-Head ' EShop の診断（読み取りのみ。ファイルは変えない）'

    $repo = if ($EShopDir) { (Resolve-Path -LiteralPath $EShopDir -ErrorAction SilentlyContinue).Path } else { Find-EShopDir (Get-Location).Path }
    if (-not $repo -or -not (Test-Path (Join-Path $repo 'backend\app\main.py'))) {
        Write-Mark 'NG' 'EShop のフォルダが見つからない'
        Write-Host "        カレント: $((Get-Location).Path)" -ForegroundColor DarkGray
        Write-Host '        VS Code で EShop フォルダを開いたターミナルで実行するか、-EShopDir で場所を指定する' -ForegroundColor Yellow
        Write-Host '        まだ clone していないなら、01-01 手順1 からやり直す' -ForegroundColor Yellow
        return
    }
    $script:Dx = @{ Repo = $repo; Src = (Join-Path $repo 'backend'); Hooks = @() }
    $br = "$(@(Invoke-DxGit branch --show-current)[0])".Trim()
    if ($br -match '^(fatal|error):') { $br = '' }
    $script:Dx.Branch = $br
    $script:Dx.Stage = switch ($br) { 'main' { 'No.1・No.2' } 'coupon' { 'No.3以降' } default { '判定できない' } }
    $null = @(Invoke-DxGit rev-parse --verify --quiet "origin/$br")
    $script:Dx.Base = if ($br -and $LASTEXITCODE -eq 0) { "origin/$br" } else { 'HEAD' }

    $out = if ($OutDir) { $OutDir } else { Split-Path $repo -Parent }
    $script:DxRecord = Join-Path $out "eshop-diagnose-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"

    Set-CheckList
    if ($Network) {
        # 3章のステップをそのまま使う。判定の文面は講師向け（事前確認書の章番号が出る）
        Initialize-Redaction
        Set-StepList
        foreach ($sid in '3-2-1', '3-2-2', '3-2-3', '3-4-1', '3-4-2', '3-5-b', '3-6-a') {
            $s = $script:Steps | Where-Object { $_.Id -eq $sid } | Select-Object -First 1
            if ($s) {
                $script:Checks += [pscustomobject]@{
                    Id = $s.Id; Group = 'ネットワーク'; Title = $s.Title; Ref = '事前確認書 3章（講師向け）'
                    Cmd = $s.Cmd; Hint = $s.Hint; TimeKey = $null
                }
            }
        }
    }

    Write-Host @"
  スクリプトの版 : $script:ScriptVersion
  EShop          : $repo
  ブランチ       : $(if ($br) { $br } else { '（なし）' })（$($script:Dx.Stage)）
  項目           : $($script:Checks.Count)件$(if ($Network) { '（通信の確認を含む）' })$(if ($SkipTest) { '（pytest は実行しない）' })
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
        $r = Invoke-Step $c
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
    if (-not $Network) {
        Write-Host ''
        Write-Host '  ログイン・pip install・git fetch など通信が疑わしいときは、講師の指示で -Network を付けて実行し直す' -ForegroundColor DarkGray
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

# 講座当日の診断。リハーサルの置き場（C:\rehearsal-<日付>）を作ったり、環境変数を控えたり
# する前に分ける。受講者のPCに要らないフォルダを作らないため
if ($Diagnose) {
    Invoke-Diagnose
    return
}

# 既定の置き場を決める。デスクトップは Known Folder Move で OneDrive 配下へ
# 付け替えられていることがあり、そこへ clone すると .venv と .git がまるごと
# クラウドへ同期される。6章の所要時間の実測が当てにならなくなり、同期中の
# ロックで pip install や git switch が落ちることもある。
# 作業フォルダと記録を同じ1フォルダにまとめ、7-3でフォルダごと片付くようにする。
function Get-DefaultBase {
    # 実行ポリシー対策の起動（冒頭の起動方法3）では $PSScriptRoot が空になる。
    # 貸与機ではこの経路がむしろ本命なので、$MaterialRoot と同じくカレントに
    # フォールバックする。案内している手順は clone したフォルダへ Set-Location
    # してから相対パスで呼ぶ形なので、カレントはスクリプトの置き場になる。
    $here = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

    # スクリプトを rehearsal-<日付> の中へ直に置く使い方。このときは親がドライブ直下に
    # なるので、下の「親を使う」には乗せられない。
    if ((Split-Path $here -Leaf) -match '^rehearsal-\d{8}$') { return $here }

    # 置き場は「スクリプトを置いたフォルダの親」にする。手で作ったフォルダへ clone して
    # あれば作業物と記録もそこにまとまり、-WorkDir と -OutDir を渡さずに済む。
    # 前日に社内で clone しておく段取りでも、置き場が実行日で割れない。
    # 次の3つを満たすときだけ。外すと置き場が意図しない場所に決まる。
    #   ・$here がスクリプトの置き場である（docs-template が並んでいる）。起動方法3で
    #     カレントが別の場所だったときに、その親を取り違えないため
    #   ・正本を直接実行していない。正本の親は SW編 で、教材リポジトリに書き込んでしまう
    #   ・親がドライブ直下でなく、OneDrive配下でもない。前者は C:\ に記録を置いてしまう。
    #     後者は .venv と .git が同期対象になり、6章の実測が当てにならなくなる
    #     （デスクトップを既定にしていないのと同じ理由）
    if ($script:ScriptVersion -notmatch '未配備' -and (Test-Path (Join-Path $here 'docs-template'))) {
        $parent = Split-Path $here -Parent
        if ($parent -and (Split-Path $parent -Parent) -and $parent -notmatch '(?i)OneDrive' -and (Test-Path $parent)) {
            return $parent
        }
    }

    # システムドライブ直下は標準ユーザーでもフォルダを作れる。エクスプローラーで
    # 見えるので消し忘れにくく、日付が入るので前回の残りとも区別できる。
    # GPOで絞られている機材のために、利用者フォルダ直下へ退避する。AppData配下は
    # 同期こそされないが見えない場所なので、消し忘れる方が怖い。
    # 作れるかは実際に作って確かめる。試し書きして消す形だと、要らない書き込みが
    # 増えるうえ、消し損ねても気づけない。
    $name = "rehearsal-$(Get-Date -Format 'yyyyMMdd')"
    foreach ($root in "$env:SystemDrive\", $env:USERPROFILE) {
        if (-not $root) { continue }
        $p = Join-Path $root $name
        try { New-Item -ItemType Directory -Force -Path $p -ErrorAction Stop | Out-Null; return $p } catch { }
    }
    return (Join-Path ([Environment]::GetFolderPath('Desktop')) $name)
}

# 両方とも指定されているなら既定は要らない。要らないフォルダを作らない
$script:DefaultBase = if ($WorkDir -and $OutDir) { $null } else { Get-DefaultBase }
$script:WorkRoot = if ($WorkDir) { $WorkDir } else { $script:DefaultBase }
$script:RepoDir = Join-Path $script:WorkRoot 'EShop'
$script:SrcDir = Join-Path $script:RepoDir 'backend'
$script:OutRoot = if ($OutDir) { $OutDir } else { $script:DefaultBase }
$script:MaterialRoot = if ($MaterialDir) { $MaterialDir } elseif ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
# 7-2-b で「開始時点に戻す」ために、いまのUser環境変数を控える。
# 元から設定されている値を消してしまわないようにするため。実行する機材に
# proxy や PIP_CERT が元から入っていることがあり、無条件に削除すると事故になる。
$script:EnvNames = @('HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'PIP_CERT', 'NODE_EXTRA_CA_CERTS')
# PATH は $script:EnvNames に入れない。丸ごと戻すと、リハーサル中にインストーラが正しく
# 足した分まで消してしまう。7-2-b では増えた項目の報告だけを行う。
$script:UserPathSnapshot = [Environment]::GetEnvironmentVariable('PATH', 'User')
$script:EnvSnapshot = @{}
foreach ($n in $script:EnvNames) {
    $script:EnvSnapshot[$n] = [Environment]::GetEnvironmentVariable($n, 'User')
}
Initialize-Redaction

# 実行ポリシーは変えない前提だが、変わっていないことは確かめておく（7-2-bで報告する）
$script:PolicySnapshot = try { (Get-ExecutionPolicy -Scope CurrentUser -ErrorAction Stop).ToString() } catch { '(取得できない)' }

Set-StepList

$targetChapters = if ($Chapter) { $Chapter | ForEach-Object { "$_" } } else { @('2', '3', '4', '5', '6', '7') }
$script:TargetChapters = $targetChapters
$steps = $script:Steps | Where-Object { $targetChapters -contains $_.Ch }
# 5章の挙動確認は社内で確定させるもので、貸与機では測れない。章を指定していないときは
# 対象から外し、-Chapter 5 と明示したときだけ実施する。
if (-not $Chapter) { $steps = $steps | Where-Object { $_.Site -ne 'materials' } }
$total = @($steps).Count
# 中断したときに「全何件のうち何件を実施したか」を記録へ書くため、関数からも見えるようにする
$script:TotalSteps = $total
# 5章が丸ごと外れることがある。指定した章ではなく、実際に走る章を記録に書く
$script:TargetChapters = @($steps | ForEach-Object { $_.Ch } | Select-Object -Unique | Sort-Object)
if ($script:TargetChapters.Count -eq 0) { $script:TargetChapters = @('(該当なし)') }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:RecordPath = Join-Path $script:OutRoot "precheck-result-$stamp.md"
$script:StepListPath = Join-Path $script:OutRoot "precheck-steps-$stamp.md"
if (-not (Test-Path $script:OutRoot)) { New-Item -ItemType Directory -Force -Path $script:OutRoot | Out-Null }

Write-Head ' 事前確認書 第I部（実機確認）'
Write-Host @"
  スクリプトの版: $script:ScriptVersion
  対象章       : $($script:TargetChapters -join ', ')  （全 ${total}ステップ）
  作業フォルダ : $script:WorkRoot
  テンプレート : $script:MaterialRoot\docs-template
  記録の出力先 : $script:OutRoot
"@ -ForegroundColor Gray

if ($script:WorkRoot -eq $script:OutRoot) {
    Write-Host '  作業物と記録を同じフォルダにまとめてある。7-3ではこのフォルダごと消せばよい' -ForegroundColor DarkGray
} else {
    Write-Host '  作業物と記録が別のフォルダにある。7-3で両方を消すこと' -ForegroundColor Yellow
}

Write-Host ''
if (-not $Auto -and -not $DryRun) {
    $stop = @($steps | Where-Object { $_.Kind -ne 'auto' }).Count
    Write-Host ("  ・止まるのは人が操作・判断する{0}箇所だけ。残りは確認を求めずに流す" -f $stop) -ForegroundColor DarkGray
    Write-Host '  ・自動で流したステップの判定がNGになったときは、その場で止まる' -ForegroundColor DarkGray
    if (-not $Chapter) {
        Write-Host '  ・社内で確定させる5章の挙動確認（5-2〜5-9）は対象外。実施するときは -Chapter 5' -ForegroundColor DarkGray
    }
}
if ($Auto) {
    Write-Host '  -Auto: 止まらずに最後まで走らせる' -ForegroundColor Yellow
    Write-Host '    ・判定の根拠があるステップは自動で判定し、無いものは「自動」として記録する' -ForegroundColor DarkGray
    if ($AllowChanges) {
        Write-Host '    ・-AllowChanges により、機材の状態を変えるステップも実行する' -ForegroundColor Red
    } else {
        Write-Host '    ・機材の状態を変えるステップは実行しない（-AllowChanges で実行する）' -ForegroundColor DarkGray
    }
    Write-Host '    ・手動操作と聞き取りは「未実施」として記録し、飛ばす' -ForegroundColor DarkGray
}
Write-Host ''
if ($DryRun) {
    Write-Host "  ステップ一覧の出力先 : $script:StepListPath" -ForegroundColor Green
} else {
    Write-Host "  判定と出力の記録     : $script:RecordPath" -ForegroundColor Green
    Write-Host '  （1ステップごとに書き足すので、途中で中断しても残る）' -ForegroundColor DarkGray
}

# 貸与機のデスクトップが客先テナントのOneDrive配下へ付け替えられていることがある。
# 既定の置き場では避けているが、-WorkDir / -OutDir で指定された場合に備えて両方を見る。
$onDrive = @()
if ($script:WorkRoot -match '(?i)OneDrive') { $onDrive += "作業フォルダ : $script:WorkRoot" }
if ($script:OutRoot -match '(?i)OneDrive') { $onDrive += "記録の出力先 : $script:OutRoot" }
if ($onDrive.Count -gt 0) {
    Write-Host ''
    Write-Host '  OneDrive配下を指している。クラウドへ同期される' -ForegroundColor Red
    $onDrive | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
    Write-Host '  作業フォルダがOneDriveの下にあると .venv と .git まで同期され、6章の所要時間の' -ForegroundColor Red
    Write-Host '  実測が当てにならなくなる。ロックがかかって pip install が落ちることもある' -ForegroundColor Red
    Write-Host '  記録は7-3で機材から消してもクラウド側に残る' -ForegroundColor Red
    $example = Join-Path "$env:SystemDrive\" "rehearsal-$(Get-Date -Format 'yyyyMMdd')"
    Write-Host ("    例: -WorkDir {0} -OutDir {0}" -f $example) -ForegroundColor DarkGray
}

try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Host ''
        Write-Host '  このスクリプトを管理者権限で実行している。受講者と同じ権限で実施するため、' -ForegroundColor Red
        Write-Host '  昇格していない通常のターミナルで開き直すことを勧める（第I部 1-2 の原則2）' -ForegroundColor Red
    } else {
        Write-Host ''
        Write-Host '  昇格していない通常の権限で実行中（受講者と同じ条件）' -ForegroundColor Green
    }
} catch { }

if ($DryRun) {
    Write-Host ''
    Write-Host '  -DryRun: 何も実行せず、全ステップの内容だけを表示する' -ForegroundColor Yellow
    $i = 0
    foreach ($s in $steps) { $i++; Show-Step $s $i $total }
    Write-Host ''
    Write-Rule '='
    Write-Host " 下見おわり（${total}ステップ）" -ForegroundColor Cyan
    Write-Rule '='
    try {
        $saved = Save-StepList $steps
        Write-Host ''
        Write-Host "  ステップ一覧を書き出した: $saved" -ForegroundColor Green
    } catch {
        Write-Host ''
        Write-Host "  ステップ一覧の書き出しに失敗した: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ''
    return
}

if (-not $NoTranscript) {
    $tpath = Join-Path $script:OutRoot 'rehearsal-check.txt'
    try {
        Start-Transcript -Path $tpath -Append -ErrorAction Stop | Out-Null
        Write-Host ''
        Write-Host "  記録を開始した: $tpath" -ForegroundColor Green
    } catch {
        Write-Host ''
        Write-Host "  Start-Transcript を開始できなかった（続行する）: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if (-not $Auto) {
    $null = Read-Key '準備ができたら [Enter] で開始する（[q]=中断）'
}

$index = 0
foreach ($step in $steps) {
    $index++
    if ($script:Aborted) { break }

    Show-Step $step $index $total

    # ---- info ステップ
    if ($step.Kind -eq 'info') {
        switch ($step.Id) {
            '4-0' {
                Write-Host ''
                Write-Label '作業' $script:WorkRoot 'White'
                Write-Label 'テンプレ' (Join-Path $script:MaterialRoot 'docs-template') 'White'
                Write-Label '記録' $script:OutRoot 'White'
                Write-Host '  ここから先はファイルを作る。場所を変えるなら中断して -WorkDir を指定し直す' -ForegroundColor DarkGray
                Write-Host '  （2章の時点で記録の書き出しは始まっているので、-OutDir はここでは変えられない）' -ForegroundColor DarkGray
                Write-Host ''
                Write-Host '  4章の前提' -ForegroundColor Cyan
                foreach ($c in 'git', 'python') {
                    $cmd = Get-Command $c -ErrorAction SilentlyContinue
                    if ($cmd) { Write-Host ("    {0,-8} {1}" -f $c, $cmd.Source) -ForegroundColor Green }
                    else { Write-Host ("    {0,-8} 見つからない" -f $c) -ForegroundColor Red }
                }
                $tpl = Join-Path $script:MaterialRoot 'docs-template'
                $n = @(Get-ChildItem (Join-Path $tpl '*.md') -ErrorAction SilentlyContinue).Count
                # -MaterialDir の指定ミスと、配備物の欠落を切り分けられるようにする
                if ($n -gt 0) { Write-Host ("    {0,-8} {1} （{2}件）" -f 'テンプレ', $tpl, $n) -ForegroundColor Green }
                elseif (-not (Test-Path $tpl)) { Write-Host ("    {0,-8} フォルダが無い: {1}（4-4-01で必要。-MaterialDir で指定する）" -f 'テンプレ', $tpl) -ForegroundColor Red }
                else { Write-Host ("    {0,-8} *.mdが0件: {1}（4-4-01で必要。配備物を確認する）" -f 'テンプレ', $tpl) -ForegroundColor Red }
            }
            '6'   { Show-Timings }
            '7-3-b' {
                Write-Host ''
                Write-Host '  講師へ渡す記録は2つあり、扱いが違う' -ForegroundColor Cyan
                Write-Host ("    {0}" -f $script:RecordPath) -ForegroundColor White
                Write-Host '      判定・所要時間・各ステップの出力。客先のネットワーク情報は伏せ字にしてある' -ForegroundColor DarkGray
                Write-Host ("    {0}" -f (Join-Path $script:OutRoot 'rehearsal-check.txt')) -ForegroundColor White
                Write-Host '      画面に出たものすべて。伏せ字にしていないので、プロキシのアドレスや' -ForegroundColor DarkGray
                Write-Host '      入力した文字がそのまま残る' -ForegroundColor DarkGray
                Write-Host ''
                Write-Host '  受け渡しはTeamsの会議チャットに添付する' -ForegroundColor Cyan
                Write-Host ''
                Write-Host '  渡したあとに、機材に残した次のものを消す（講師専用資料を残さない）' -ForegroundColor Cyan
                if ($script:WorkRoot -eq $script:OutRoot) {
                    Write-Host ("    {0}  （作業物と記録。フォルダごと）" -f $script:OutRoot) -ForegroundColor White
                } else {
                    Write-Host ("    {0}  （作業物。フォルダごと）" -f $script:WorkRoot) -ForegroundColor White
                    Write-Host ("    {0}  （記録。rehearsal-check.txt と precheck-*.md）" -f $script:OutRoot) -ForegroundColor White
                }
                # クローンが置き場の中にあるなら、上の行で一緒に消える。別に出すと
                # 「2箇所消す」と読まれてしまう。
                $matInside = $false
                foreach ($r in $script:WorkRoot, $script:OutRoot) {
                    if (-not $r) { continue }
                    $a = $script:MaterialRoot.TrimEnd('\')
                    $b = $r.TrimEnd('\')
                    if ($a -eq $b -or $a.ToLower().StartsWith($b.ToLower() + '\')) { $matInside = $true }
                }
                if (-not $matInside) {
                    Write-Host ("    {0}  （rehearsalブランチのクローンごと）" -f $script:MaterialRoot) -ForegroundColor White
                }
                Write-Host '  この削除は自動では行わない（講師自身のPCで実行した場合に教材のクローンを消してしまうため）' -ForegroundColor DarkGray
                Write-Host ''
                Write-Host '  rehearsal-check.txt は客先のネットワーク情報を含んだままなので、渡したあとの' -ForegroundColor Yellow
                Write-Host '  取り扱いに注意する。社外・他案件へ出さない' -ForegroundColor Yellow
            }
        }
        if (-not $Auto) {
            $ans = Read-Key '[Enter]=確認した   [q]=中断'
            if ($ans.ToLower() -eq 'q') { $script:Aborted = $true; break }
        }
        Add-Result $step '確認' '' ''
        continue
    }

    # ---- ask ステップ
    if ($step.Kind -eq 'ask') {
        if ($Auto) {
            Add-Result $step '未実施' '' '自動モードのため聞き取りをしていない'
            Write-Host '  人に尋ねる項目のため未実施として記録' -ForegroundColor DarkGray
            continue
        }
        $ans = Read-Key '回答を入力   [Enter]のみ=スキップ   [q]=中断'
        if ($ans.ToLower() -eq 'q') { $script:Aborted = $true; break }
        if (-not $ans) {
            Add-Result $step 'スキップ' '' ''
            Write-Host '  スキップとして記録' -ForegroundColor DarkGray
            continue
        }
        if ($step.Id -eq '3-4-3') {
            Add-Result $step '記録' '' 'URLは記録しない'
            Write-Host '  受け取った（URLは記録しない）' -ForegroundColor Green
        } else {
            Add-Result $step '記録' $ans ''
            Write-Host "  記録した: $ans" -ForegroundColor Green
        }

        # 3-4-3 だけは入力されたURLの到達性も測る（URLは記録に残さない）
        if ($step.Id -eq '3-4-3' -and $ans -match '^https?://') {
            Write-Rule
            $code = (curl.exe -s -o NUL -w "%{http_code}" --max-time 20 $ans 2>&1)
            Write-Host "  共有リンクの到達性 => $code" -ForegroundColor White
            Write-Host '  403や401は「到達はしている」だけ。パスワード付きリンクの未認証でも返る' -ForegroundColor DarkGray
            Write-Host '  開けるか・md/PDF/xlsxが表示できるか・ダウンロードできるかは 8-3 で別に確認する' -ForegroundColor DarkGray
            Write-Rule
            $script:Captured['3-4-3'] = "共有リンクの到達性 => $code（403や401は到達のみ）"
            $script:Results[-1].Output = "共有リンクの到達性 => $code（URLは記録しない。403や401は到達のみで、開けるかは8-3で確認する）"
            # Add-Result のときの書き出しは既に終わっているため、書き足した分をここで反映する。
            # そうしないと、この直後に中断したときに到達性の結果だけ記録から落ちる。
            try { Save-Record | Out-Null } catch { }
        }
        continue
    }

    # ---- manual ステップ
    if ($step.Kind -eq 'manual') {
        if ($Auto) {
            Add-Result $step '未実施' '' '自動モードのため手動操作をしていない'
            Write-Host '  人が操作する項目のため未実施として記録' -ForegroundColor DarkGray
            continue
        }
        $ans = Read-Key '[Enter]=実施した   [s]=スキップ   [q]=中断'
        if ($ans.ToLower() -eq 'q') { $script:Aborted = $true; break }
        if ($ans.ToLower() -eq 's') {
            Add-Result $step 'スキップ' '' ''
            Write-Host '  スキップとして記録' -ForegroundColor DarkGray
            continue
        }
        $obs = Read-Host '  観測した結果（画面に出た内容・エラー文面。無ければEnter）'
        Read-Verdict $step $obs -1 $null
        continue
    }

    # ---- change ステップ（既定はスキップ）
    if ($step.Kind -eq 'change') {
        Write-Host ''
        Write-Host '  このステップは機材の状態を変える。7章で元へ戻す対象になる' -ForegroundColor Red
        if ($step.SkipImpact) { Write-Host "  $($step.SkipImpact)" -ForegroundColor Yellow }
        if ($Auto) {
            if (-not $AllowChanges) {
                $memo = '自動モードでは設定変更を実行しない（-AllowChanges で実行する）'
                if ($step.SkipImpact) { $memo += "。$($step.SkipImpact)" }
                Add-Result $step 'スキップ' '' $memo
                Write-Host '  スキップとして記録（実行するには -AllowChanges を付ける）' -ForegroundColor DarkGray
                continue
            }
            # いまは該当するステップが無いが、実行中に入力を求める change ステップを
            # 足したときに -Auto が固まらないようにするための歯止め
            if ($step.NeedsInput) {
                Add-Result $step 'スキップ' '' '実行中に入力を求めるため自動モードでは実行できない'
                Write-Host '  実行中に入力を求めるステップのためスキップ' -ForegroundColor DarkGray
                continue
            }
            $r = Invoke-Step $step
            Set-AutoVerdict $step $r
            continue
        }
        # ここだけ Enter が「やらない」側になる。影響の大きいステップなので明示する
        $ans = Read-Key '[y]=実行する   [Enter]=スキップ ← ここだけ既定が「やらない」   [q]=中断'
        if ($ans.ToLower() -eq 'q') { $script:Aborted = $true; break }
        if ($ans.ToLower() -ne 'y') {
            $memo = '設定変更のため実行しなかった'
            if ($step.SkipImpact) { $memo += "。$($step.SkipImpact)" }
            Add-Result $step 'スキップ' '' $memo
            Write-Host '  スキップとして記録' -ForegroundColor DarkGray
            continue
        }
        $r = Invoke-Step $step
        Read-Verdict $step $r.Text $r.Seconds $r.Suggest
        continue
    }

    # ---- auto ステップ。確認を求めずに流し、NGのときだけ止まる
    $r = Invoke-Step $step
    Set-AutoVerdict $step $r
    if (-not $Auto -and $r.Suggest -eq 'NG') {
        Write-Host ''
        Write-Host '  判定がNGのため、ここで止まる' -ForegroundColor Red
        $ans = Read-Key '[Enter]=続ける   [m]=メモを追記   [q]=中断'
        if ($ans.ToLower() -eq 'q') { $script:Aborted = $true; break }
        if ($ans.ToLower() -eq 'm') {
            $memo = Read-Host '  メモ'
            if ($memo) {
                $script:Results[-1].Memo = $memo
                try { Save-Record | Out-Null } catch { }
            }
        }
    }
}

# ---------------------------------------------------------------- まとめ

Write-Head ' 実施結果'

if ($script:Aborted) {
    Write-Host ("  途中で中断した（全 {0}ステップ中 {1}ステップを実施）" -f $script:TotalSteps, $script:Results.Count) -ForegroundColor Yellow
    Write-Host '  続けるときは -Chapter で残りの章を指定する' -ForegroundColor DarkGray
    Write-Host ''
}

if ($script:Results.Count -eq 0) {
    Write-Host '  記録はない' -ForegroundColor DarkGray
} else {
    foreach ($r in $script:Results) {
        Write-Host ('  {0,-6} {1,-10} {2}' -f $r.Verdict, $r.Id, $r.Title) -ForegroundColor (Get-MarkColor $r.Verdict)
    }
    Write-Host ''
    $ng = @($script:Results | Where-Object Verdict -eq 'NG')
    $hold = @($script:Results | Where-Object Verdict -eq '保留')
    $notdone = @($script:Results | Where-Object Verdict -eq '未実施')
    $autov = @($script:Results | Where-Object Verdict -eq '自動')
    Write-Host ("  OK {0} / NG {1} / 保留 {2} / 自動 {3} / 未実施 {4} / その他 {5}" -f `
        @($script:Results | Where-Object Verdict -eq 'OK').Count, $ng.Count, $hold.Count, $autov.Count, $notdone.Count,
        @($script:Results | Where-Object { $_.Verdict -notin 'OK', 'NG', '保留', '自動', '未実施' }).Count) -ForegroundColor White
    if ($autov.Count -gt 0) {
        Write-Host ''
        Write-Host '  自動（判定の根拠が無いステップ。記録の出力を見て講師が判断する）' -ForegroundColor DarkGray
        $autov | ForEach-Object { Write-Host "    $($_.Id) $($_.Title)" -ForegroundColor DarkGray }
    }
    if ($notdone.Count -gt 0) {
        Write-Host ''
        Write-Host '  未実施（人が操作・確認する必要がある。-Auto を付けずに実施する）' -ForegroundColor Yellow
        $notdone | ForEach-Object { Write-Host "    $($_.Id) $($_.Title)" -ForegroundColor Yellow }
    }
    if ($ng.Count -gt 0) {
        Write-Host ''
        Write-Host '  NG（第II部の10章で依頼先と期限を決める）' -ForegroundColor Red
        $ng | ForEach-Object { Write-Host "    $($_.Id) $($_.Title)" -ForegroundColor Red }
    }
    if ($hold.Count -gt 0) {
        Write-Host ''
        Write-Host '  保留（講師が引き取る）' -ForegroundColor Yellow
        $hold | ForEach-Object { Write-Host "    $($_.Id) $($_.Title)" -ForegroundColor Yellow }
    }
}

if ($script:Timings.Count -gt 0) { Show-Timings }

# 起動時に控えた値と突き合わせる。スクリプトが設定していなくても、インストーラや
# 手で足した分はここに出る。変数名だけを出し、値は出さない。
$envDiff = @()
foreach ($n in $script:EnvNames) {
    if ([Environment]::GetEnvironmentVariable($n, 'User') -ne $script:EnvSnapshot[$n]) { $envDiff += $n }
}
if ($envDiff.Count -gt 0) {
    Write-Host ''
    Write-Host "  User環境変数が起動時から変わっている: $($envDiff -join ', ')" -ForegroundColor Red
    Write-Host '  7-2-b を実行して開始時点の値に戻すこと' -ForegroundColor Red
}

try {
    $saved = Save-Record
    Write-Host ''
    Write-Host "  記録: $saved" -ForegroundColor Green
} catch {
    Write-Host ''
    Write-Host "  記録の書き出しに失敗した: $($_.Exception.Message)" -ForegroundColor Red
}

if (-not $NoTranscript) {
    try { Stop-Transcript | Out-Null } catch { }
}

Write-Host ''
Write-Host '  記録は機材から消す前に講師へ渡す（7-3）' -ForegroundColor White
Write-Host ''
