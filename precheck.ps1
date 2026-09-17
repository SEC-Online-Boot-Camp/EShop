<#
    事前確認書 第I部（実機確認）の対話型ランナー

    1ステップずつ「これから実行するコマンド」を表示し、Enterで実行して結果を表示する。
    判定（OK / NG / 保留）とメモをその場で入力し、最後に記録をファイルへ書き出す。

    管理者権限は不要。機材の状態を変えるステップは <設定変更> と表示され、
    既定はスキップで、明示的に y を押したときだけ実行する。

    リハーサル機での取得（受講者が使う main / No3 は取得されない）

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

    引数

        -DryRun          何も実行せず、全ステップの内容だけを順に表示する（下見用）
        -Chapter 2,3     指定した章だけを実施する（既定は2〜7章すべて）
        -WorkDir <path>  EShopをcloneする作業フォルダ（既定 Desktop\rehearsal）
        -MaterialDir <p> docs-template があるフォルダ（4-4-01で使う。既定はこのスクリプトの場所）
        -OutDir <path>   記録の出力先（既定 Desktop）
        -NoTranscript    Start-Transcriptを使わない
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [string[]]$Chapter,
    [string]$WorkDir,
    [string]$MaterialDir,
    [string]$OutDir,
    [switch]$NoTranscript
)

$ErrorActionPreference = 'Continue'

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
        [scriptblock]$When,
        [string]$Ask,
        [string]$TimeKey
    )
    $script:Steps += [pscustomobject]@{
        Id = $Id; Ch = $Ch; Title = $Title; Kind = $Kind
        Purpose = $Purpose; Expect = $Expect; Show = $Show
        Cmd = $Cmd; Hint = $Hint; When = $When; Ask = $Ask; TimeKey = $TimeKey
    }
}

function Add-Result {
    param($Step, [string]$Verdict, [string]$Output, [string]$Memo, [double]$Seconds = -1)
    $script:Results += [pscustomobject]@{
        Id = $Step.Id; Ch = $Step.Ch; Title = $Step.Title; Kind = $Step.Kind
        Command = (Get-ShowText $Step)
        Verdict = $Verdict; Output = $Output; Memo = $Memo
        Seconds = $Seconds; At = (Get-Date).ToString('HH:mm:ss')
    }
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
    return 'python'
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
        -Cmd {
            Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' |
                Select-Object ProductName, DisplayVersion, CurrentBuild, UBR
        }

    New-Step -Id '2-1-b' -Ch '2' -Title 'ログインユーザーの権限' -Kind ask `
        -Purpose '受講者と同じ権限で実施しているかを確かめる（管理者に昇格しない）' `
        -Ask 'この端末のログインユーザーは 管理者 / 標準ユーザー のどちらですか'

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
                Write-Host '  → グループポリシーで縛られている。Set-ExecutionPolicy -Scope CurrentUser は効かないため、' -ForegroundColor Magenta
                Write-Host '     01-01手順書は代替1行だけに絞る（11章へ記録）' -ForegroundColor Magenta
            } else {
                Write-Host '  → ポリシーによる縛りは無い。activate の可否は 4-3 の手順8で確定する' -ForegroundColor Magenta
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
                if ($free -lt 2) { Write-Host "  → 空きが2GBを下回っている（$free GB）" -ForegroundColor Red }
                else { Write-Host "  → 空きは足りている（$free GB）" -ForegroundColor Magenta }
            }
        }

    New-Step -Id '2-1-e' -Ch '2' -Title 'ウイルス対策・EDRの介入' -Kind ask `
        -Purpose 'インストーラやスクリプトがブロックされないかを見る' `
        -Ask '気づいた事象があれば入力（無ければEnter）'

    New-Step -Id '2-1-f' -Ch '2' -Title '機材の台数・構成の揃い' -Kind ask `
        -Purpose '1台だけ違う構成だと当日詰まる' `
        -Ask '貸与元・台数・予備機の有無、全台が同じ構成か'

    New-Step -Id '2-2-a' -Ch '2' -Title 'VS Codeの版' -Kind auto `
        -Expect '導入済みであること' `
        -Cmd { code --version }

    New-Step -Id '2-2-b' -Ch '2' -Title 'Pythonの版と実体パス' -Kind auto `
        -Purpose '依存パッケージが完全固定のため、版によってwheelが無くビルドに失敗する（4-2）' `
        -Expect '3.11以上。WindowsApps配下のエイリアスでないこと' `
        -Cmd {
            python --version
            (Get-Command python -ErrorAction SilentlyContinue).Source
        } `
        -Hint {
            param($text)
            if ($text -match 'Python\s+3\.(\d+)') {
                $minor = [int]$Matches[1]
                if ($minor -lt 11) { Write-Host "  → 3.11未満（3.$minor）。要件を満たさない" -ForegroundColor Red }
                else { Write-Host "  → 3.$minor で要件を満たす" -ForegroundColor Magenta }
            }
            if ($text -match 'WindowsApps') {
                Write-Host '  → Microsoft Storeのエイリアスを指している。実体のPythonが入っていない' -ForegroundColor Red
            }
        }

    New-Step -Id '2-2-c' -Ch '2' -Title 'Gitの版' -Kind auto `
        -Expect '導入済みであること' `
        -Cmd { git --version }

    New-Step -Id '2-2-d' -Ch '2' -Title 'PowerShellの版' -Kind auto `
        -Purpose '5.1と7ではプロキシの読み先が違う（3-1）' `
        -Expect 'VS Codeの既定ターミナルがどちらかを記録する' `
        -Cmd { $PSVersionTable.PSVersion; "PSEdition = $($PSVersionTable.PSEdition)" }

    New-Step -Id '2-2-e' -Ch '2' -Title 'Excelの有無' -Kind ask `
        -Purpose '01-05-セキュリティチェックシート.xlsx の編集に必要' `
        -Ask 'Excelで xlsx を編集できますか（有 / 無）'

    # ====================== 3章 ネットワークとプロキシ ======================

    New-Step -Id '3-2-1' -Ch '3' -Title '環境変数（3スコープ）' -Kind auto `
        -Purpose 'curl・pip・Claude Codeはここだけを見る' `
        -Expect '何も出なければ未設定。小文字の場合もある' `
        -Cmd {
            Get-ChildItem Env: | Where-Object Name -match 'proxy' | Format-Table -AutoSize
            'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY' | ForEach-Object { "User    {0} = {1}" -f $_, [Environment]::GetEnvironmentVariable($_, 'User') }
            'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY' | ForEach-Object { "Machine {0} = {1}" -f $_, [Environment]::GetEnvironmentVariable($_, 'Machine') }
        }

    New-Step -Id '3-2-2' -Ch '3' -Title 'Windows側の設定（WinINET・PAC・WinHTTP）' -Kind auto `
        -Purpose 'ブラウザとVS Codeが見る設定' `
        -Expect 'ProxyEnable / ProxyServer / AutoConfigURL / ProxyOverride を記録する' `
        -Cmd {
            Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' |
                Select-Object ProxyEnable, ProxyServer, ProxyOverride, AutoConfigURL, AutoDetect
            netsh winhttp show proxy
        } `
        -Hint {
            param($text)
            if ($text -match 'AutoConfigURL\s*:\s*\S') { Write-Host '  → PAC方式。アドレスは 3-2-3 で解決する' -ForegroundColor Magenta }
            if ($text -match 'Direct access') { Write-Host '  → WinHTTPは直結（プロキシなし、または透過型）' -ForegroundColor Magenta }
            if ($text -match '<local>') { Write-Host '  → ローカルアドレスは迂回される（Swagger UIの表示に必要）' -ForegroundColor Magenta }
        }

    New-Step -Id '3-2-3' -Ch '3' -Title '実効プロキシの解決（PACでもアドレスが判る）' -Kind auto `
        -Purpose '01-01手順書のプレースホルダに入れる実値を得る' `
        -Expect 'bypass列とセットで読む。bypass=Trueの行はプロキシを経由しない' `
        -Cmd {
            $p = [System.Net.WebRequest]::GetSystemWebProxy()
            'https://claude.ai', 'https://api.anthropic.com', 'https://downloads.claude.ai', 'https://github.com', 'https://pypi.org', 'https://files.pythonhosted.org', 'https://marketplace.visualstudio.com', 'http://127.0.0.1:8000/docs' |
                ForEach-Object { $u = [Uri]$_; "{0,-45} -> {1}  bypass={2}" -f $_, $p.GetProxy($u), $p.IsBypassed($u) }
        }

    New-Step -Id '3-2-4' -Ch '3' -Title 'PACの中身' -Kind auto `
        -Purpose '宛先ごとの振り分けを直接読む' `
        -Expect 'PACのスクリプトが表示される' `
        -When {
            $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue).AutoConfigURL
            [bool]$v
        } `
        -Show "Invoke-WebRequest -Uri <AutoConfigURLの値> -UseBasicParsing -TimeoutSec 10 -NoProxy | Select-Object -ExpandProperty Content`n（-NoProxy は PowerShell 7 のみ。5.1 ではブラウザでURLを開いて中身を見る）" `
        -Cmd {
            $url = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').AutoConfigURL
            "AutoConfigURL = $url"
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10 -NoProxy).Content
            } else {
                'PowerShell 5.1 には -NoProxy が無い。ブラウザで上のURLを開いて中身を確認する'
            }
        }

    New-Step -Id '3-3' -Ch '3' -Title '判定基準の確認（読むだけ）' -Kind info `
        -Purpose 'ここを誤読すると「通っているのに遮断」と判定してしまう' `
        -Show @"
  200 / 301 / 302 / 401 / 403 / 404        到達成功（TLSとHTTP応答が成立している）
  タイムアウト・接続拒否                   遮断（プロキシ未設定かファイアウォール）
  407 Proxy Authentication Required        認証付きプロキシ → 3-6のケースD
  証明書エラー（SSL certificate problem）  TLS傍受 → 3-7
  プロキシが返す502/503・ブロック画面      許可リストに無い → IT部門へ申請
"@

    New-Step -Id '3-4-1' -Ch '3' -Title '到達性の確認（環境変数の経路 / curl.exe）' -Kind auto `
        -Purpose 'pip・git・Claude Codeと同じ経路で確かめる' `
        -Expect '各ホストのHTTPステータス。3-3の表で判定する' `
        -Cmd {
            'https://claude.ai', 'https://claude.com', 'https://platform.claude.com', 'https://api.anthropic.com', 'https://downloads.claude.ai', 'https://github.com', 'https://pypi.org/simple/', 'https://files.pythonhosted.org', 'https://marketplace.visualstudio.com' |
                ForEach-Object { "{0,-45} {1}" -f $_, (curl.exe -s -o NUL -w "%{http_code}" --max-time 20 $_ 2>&1) }
        } `
        -Hint {
            param($text)
            $bad = @()
            foreach ($line in ($text -split "`n")) {
                if ($line -match '^\s*(https\S+)\s+(\S+)\s*$') {
                    $code = $Matches[2]
                    if ($code -notmatch '^(200|301|302|401|403|404)$') { $bad += "$($Matches[1]) => $code" }
                }
            }
            if ($bad.Count -gt 0) {
                Write-Host '  → 到達できていないホスト（10章の申請対象）' -ForegroundColor Red
                $bad | ForEach-Object { Write-Host "     $_" -ForegroundColor Red }
            } else {
                Write-Host '  → 全ホストがTLSまで到達している' -ForegroundColor Magenta
            }
        }

    New-Step -Id '3-4-2' -Ch '3' -Title '到達性の確認（システム設定の経路 / ブラウザ・VS Code相当）' -Kind auto `
        -Purpose '3-4-1と食い違ったら、それが原因の切り分けになる' `
        -Expect 'curlと同じ結果か。違う場合は下のヒントを読む' `
        -Cmd {
            foreach ($u in 'https://claude.ai', 'https://api.anthropic.com', 'https://github.com', 'https://pypi.org/simple/', 'https://marketplace.visualstudio.com') {
                try { "{0,-45} {1}" -f $u, (Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 20).StatusCode }
                catch { "{0,-45} {1}" -f $u, $_.Exception.Message }
            }
        } `
        -Hint {
            param($text)
            Write-Host '  → curl(環境変数) と PowerShell(システム設定) の組み合わせで読む' -ForegroundColor Magenta
            Write-Host '     OK / OK  両系統とも設定済み。そのまま進める' -ForegroundColor Magenta
            Write-Host '     NG / OK  システム設定のみのPAC運用。環境変数の追加が必要（ケースC）' -ForegroundColor Magenta
            Write-Host '     OK / NG  環境変数のみ設定済み。ブラウザ側を 3-5 で必ず確認する' -ForegroundColor Magenta
            Write-Host '     NG / NG  遮断か未設定。3-2-3のアドレスでケースCを試す' -ForegroundColor Magenta
        }

    New-Step -Id '3-4-3' -Ch '3' -Title '教材の配布リンク（OneDrive）の到達性' -Kind ask `
        -Purpose '8-3の配布経路がこの機材から開けるか' `
        -Ask '共有リンクのURLを貼る（未確定ならEnterでスキップ）。貼った場合は続けて到達確認を行う'

    New-Step -Id '3-5-a' -Ch '3' -Title 'claude.aiへのログイン（手動）' -Kind manual `
        -Purpose 'Claude Codeの認証はブラウザを経由するため、ブラウザ側が通る必要がある' `
        -Show @"
  1. Edge で https://claude.ai を開く
  2. ログインする（メール＋コード、またはSSO）
  3. チャットを1往復する
"@ `
        -Expect 'ログインでき、応答が返ること'

    New-Step -Id '3-5-b' -Ch '3' -Title 'ローカル通信（127.0.0.1）の迂回' -Kind auto `
        -Purpose 'ここがプロキシに投げられると Swagger UI の確認で詰まる' `
        -Expect 'True であること' `
        -Cmd {
            [System.Net.WebRequest]::GetSystemWebProxy().IsBypassed([Uri]'http://127.0.0.1:8000/')
        } `
        -Hint {
            param($text)
            if ($text -match 'False') {
                Write-Host '  → 迂回されない。環境変数を設定する場合は NO_PROXY に localhost,127.0.0.1,::1 を必ず入れる' -ForegroundColor Red
            } else {
                Write-Host '  → 迂回される。Swagger UI の表示は問題ない' -ForegroundColor Magenta
            }
        }

    New-Step -Id '3-6-a' -Ch '3' -Title '判定ケースの決定' -Kind ask `
        -Purpose 'ここまでの結果で、受講者に案内する内容が決まる' `
        -Show @"
  A  全ツールがそのまま通る                              → 設定不要
  B  ブラウザとVS Codeは通るが curl・pip・git が通らない → 環境変数を設定
  C  環境変数の設定が必要                                → 次のステップで setx
  D  407が返る（認証付きプロキシ）                       → 当日対応では解決しない。IT部門へ申請
  E  TLS傍受あり                                         → 3-7へ
"@ `
        -Ask 'ケース（A / B / C / D / E）'

    New-Step -Id '3-6-b' -Ch '3' -Title 'プロキシの環境変数を設定する' -Kind change `
        -Purpose 'ケースB・Cのときだけ実施する。7-2-bで必ず削除する' `
        -Expect 'setx が成功する（新しく開くプロセスにのみ効く）' `
        -Show @"
  setx HTTP_PROXY  "http://<アドレス>:<ポート>"
  setx HTTPS_PROXY "http://<アドレス>:<ポート>"
  setx NO_PROXY    "localhost,127.0.0.1,::1"

  実行するとアドレスとポートを尋ねる。設定後はVS Codeを再起動する。
  資格情報をURLに埋める形（http://user:pass@host:port）は採用しない。
"@ `
        -Cmd {
            $addr = Read-Host '  プロキシのアドレス（例 proxy.example.local）'
            $port = Read-Host '  ポート（例 8080）'
            if (-not $addr -or -not $port) { '入力が空のため中止した'; return }
            $url = "http://${addr}:${port}"
            setx HTTP_PROXY $url
            setx HTTPS_PROXY $url
            setx NO_PROXY 'localhost,127.0.0.1,::1'
            $script:ChangedEnv = $true
            "設定した: $url （7-2で削除する）"
        }

    New-Step -Id '3-7' -Ch '3' -Title 'TLS傍受の判定' -Kind ask `
        -Purpose 'pipだけが証明書エラーで落ちるのが典型。対処は付録C' `
        -Show @"
  curl・ブラウザ・git は通るが pip だけ CERTIFICATE_VERIFY_FAILED   → 傍受あり
  git が SSL certificate problem: unable to get local issuer …      → 傍受あり（gitがOSストアを見ていない）
  すべて通る                                                        → 傍受なし、またはCA配布済み

  傍受用のルート証明書の有無と名称は IT部門に確認する（10章の依頼事項）。
  4-3の pip install を実行したあとに、ここへ戻って確定させてもよい。
"@ `
        -Ask 'TLS傍受（あり / なし / 保留）'

    # ====================== 4章 EShopの通し実行 ======================

    New-Step -Id '4-0' -Ch '4' -Title '作業フォルダの確認' -Kind info `
        -Purpose 'ここから先はファイルを作る。場所を先に確認する' `
        -Show '実行時に表示する'

    New-Step -Id '4-3-01' -Ch '4' -Title 'Claude Codeのインストール' -Kind change `
        -Purpose '受講者も同じコマンドを実行する（01-02）' `
        -Expect 'スクリプトの取得と実体のダウンロードの両方が通る' `
        -Show @"
  irm https://claude.ai/install.ps1 | iex

  Anthropicが公式に案内しているインストール方法（01-02-セットアップ手順.md に記載）。
  取得元は claude.ai、インストーラ本体の配布元は downloads.claude.ai。
  ユーザー領域に入るため管理者権限は不要。7-2で /logout と設定の削除を行う。
"@ `
        -Cmd { irm https://claude.ai/install.ps1 | iex }

    New-Step -Id '4-3-02' -Ch '4' -Title 'Claude Codeの版' -Kind auto `
        -Expect '版を記録する（本番と同一かを12章で照合する）' `
        -Cmd { claude --version }

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
  1. VS Code の拡張ビューで「Claude Code for VS Code」を検索して導入する
  2. Claude Code パネルの Sign in で認証する
"@ `
        -Expect 'インストール完了とサインインまで到達する（marketplaceとvsassetsの両方が必要）'

    New-Step -Id '4-3-05' -Ch '4' -Title 'リポジトリのclone' -Kind auto -TimeKey 'clone' `
        -Purpose 'github.com への到達をここで実測する' `
        -Expect '成功すること。所要時間を記録する（社内実測1.2秒）' `
        -Show 'git clone https://github.com/SEC-Online-Boot-Camp/EShop.git' `
        -Cmd {
            if (-not (Test-Path $script:WorkRoot)) { New-Item -ItemType Directory -Force -Path $script:WorkRoot | Out-Null }
            Push-Location $script:WorkRoot
            try {
                if (Test-Path $script:RepoDir) { "既に存在するため clone をスキップ: $($script:RepoDir)"; return }
                git clone https://github.com/SEC-Online-Boot-Camp/EShop.git 2>&1
            } finally { Pop-Location }
        }

    New-Step -Id '4-3-06' -Ch '4' -Title '仮想環境の作成' -Kind auto -TimeKey 'venv' `
        -Expect '.venv が作られる（社内実測8.5秒）' `
        -Show 'cd src ; python -m venv .venv' `
        -Cmd { Invoke-InSrc { python -m venv .venv 2>&1; "作成先: $(Join-Path $PWD '.venv')" } }

    New-Step -Id '4-3-07' -Ch '4' -Title '仮想環境の有効化（activate の可否）' -Kind auto `
        -Purpose '実行ポリシーで .ps1 が禁止されていると失敗する。代替1行が効くかをここで確定する' `
        -Expect '(.venv) 相当の状態になること。activate が失敗した場合は代替1行で通ること' `
        -Show @"
  .venv\Scripts\activate
  （失敗する場合の代替1行 = 01-01手順書に記載のもの）
  `$env:VIRTUAL_ENV="`$PWD\.venv"; `$env:PATH="`$env:VIRTUAL_ENV\Scripts;`$env:PATH"
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
                "pytest => $((Get-Command pytest -ErrorAction SilentlyContinue).Source)"
            }
        } `
        -Hint {
            param($text)
            if ($text -match 'activate（\.ps1）は失敗した') {
                Write-Host '  → 手順書は代替1行だけに絞る（11章へ記録）' -ForegroundColor Magenta
            }
            if ($text -notmatch '\.venv') {
                Write-Host '  → python/pytest が .venv 配下を指していない。ここが揃わないと以降が別環境になる' -ForegroundColor Red
            }
        }

    New-Step -Id '4-3-08' -Ch '4' -Title '依存パッケージのインストール' -Kind auto -TimeKey 'pip' `
        -Purpose '最も伸びやすい。TLS傍受があるとここだけ証明書エラーで落ちる（3-7）' `
        -Expect '成功すること（社内実測31.4秒）' `
        -Show 'pip install -r requirements.txt' `
        -Cmd { Invoke-InSrc { & (Get-VenvPython) -m pip install -r requirements.txt 2>&1 } } `
        -Hint {
            param($text)
            if ($text -match 'CERTIFICATE_VERIFY_FAILED|SSLError') {
                Write-Host '  → TLS傍受の典型。付録Cの対処へ（検証の無効化は使わない）' -ForegroundColor Red
            }
            if ($text -match 'Failed building wheel|error: subprocess-exited-with-error') {
                Write-Host '  → wheelが無くソースビルドに落ちている。Pythonの版を合わせる判断が必要（4-2）' -ForegroundColor Red
            }
        }

    New-Step -Id '4-3-09' -Ch '4' -Title '初期データの投入' -Kind auto -TimeKey 'seed' `
        -Expect '「ユーザー2件・商品5件を投入しました。」（社内実測1.9秒）' `
        -Show 'python -m app.seed' `
        -Cmd { Invoke-InSrc { & (Get-VenvPython) -m app.seed 2>&1 } }

    New-Step -Id '4-3-10' -Ch '4' -Title 'サーバー起動とSwagger UIの表示' -Kind auto `
        -Purpose '127.0.0.1がプロキシに投げられていないかを実物で確かめる' `
        -Expect 'http://127.0.0.1:8000/docs が 200 を返す' `
        -Show @"
  uvicorn app.main:app --reload
  → ブラウザで http://127.0.0.1:8000/docs を開く

  このスクリプトでは、サーバーを裏で起動して /docs のステータスを取り、最後に停止する。
"@ `
        -Cmd {
            Invoke-InSrc {
                $py = Get-VenvPython
                $proc = Start-Process -FilePath $py -ArgumentList '-m', 'uvicorn', 'app.main:app' `
                    -WorkingDirectory (Get-Location).Path -PassThru -WindowStyle Hidden
                try {
                    $code = ''
                    for ($i = 0; $i -lt 20; $i++) {
                        Start-Sleep -Seconds 1
                        $code = (curl.exe -s -o NUL -w "%{http_code}" --max-time 5 --noproxy '*' http://127.0.0.1:8000/docs 2>&1)
                        if ($code -eq '200') { break }
                    }
                    "http://127.0.0.1:8000/docs => $code"
                    if ($code -eq '200') { 'ブラウザでも開いて画面を確認する（このまま起動し続けたい場合は手動で起動し直す）' }
                } finally {
                    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force; 'サーバーを停止した' }
                }
            }
        }

    New-Step -Id '4-3-11' -Ch '4' -Title 'テストの実行（mainの基準線）' -Kind auto -TimeKey 'pytest-main' `
        -Expect '全件PASS。mainの基準は54件（社内実測8.6秒）' `
        -Show 'pytest' `
        -Cmd { Invoke-InSrc { & (Get-VenvPython) -m pytest 2>&1 } } `
        -Hint {
            param($text)
            if ($text -match '(\d+)\s+passed') {
                $n = [int]$Matches[1]
                if ($n -eq 54) { Write-Host "  → 54件PASS。基準どおり" -ForegroundColor Magenta }
                else { Write-Host "  → $n 件PASS。基準の54件と違う" -ForegroundColor Red }
            }
            if ($text -match '(\d+)\s+failed') { Write-Host "  → 失敗 $($Matches[1]) 件。mainでは全件PASSが期待値" -ForegroundColor Red }
        }

    New-Step -Id '4-4-01' -Ch '4' -Title 'No.2成果物の配置（講師が実施）' -Kind change `
        -Purpose 'No.3の手順書はNo.2の成果物を参照する。無いと4-4の手順6以降と5章の#5が実行できない' `
        -Expect 'docs/要件整理メモ.md と docs/クーポンAPI設計書.md が置かれる' `
        -Show @"
  New-Item -ItemType Directory -Force docs
  Copy-Item <rehearsalブランチ>\docs-template\*.md docs\

  リハーサルではNo.2の演習を行わないため、rehearsalブランチのダミー成果物で代用する。
  中身の妥当性は問わず、手順が実行できるかの確認が目的。
  解答例は講師専用資料なので、この経路では使わない。
"@ `
        -Cmd {
            Invoke-InRepo {
                $tpl = Join-Path $script:MaterialRoot 'docs-template'
                $files = @(Get-ChildItem (Join-Path $tpl '*.md') -ErrorAction SilentlyContinue)
                if ($files.Count -eq 0) { "docs-template が見つからない: $tpl （-MaterialDir で指定する）"; return }
                New-Item -ItemType Directory -Force docs | Out-Null
                $files | ForEach-Object { Copy-Item $_.FullName (Join-Path 'docs' $_.Name) -Force }
                Get-ChildItem docs | Select-Object Name, Length
            }
        }

    New-Step -Id '4-4-02' -Ch '4' -Title 'No3ブランチの取得と切り替え' -Kind auto -TimeKey 'fetch' `
        -Purpose 'ここで再びネットワークを使う。No.1が通っても省略しない' `
        -Expect 'git branch --show-current が No3' `
        -Show 'git fetch origin ; git switch No3 ; git branch --show-current' `
        -Cmd {
            Invoke-InRepo {
                git fetch origin 2>&1
                git switch No3 2>&1
                "current = $(git branch --show-current)"
            }
        }

    New-Step -Id '4-4-03' -Ch '4' -Title '切り替え後のファイル確認' -Kind auto `
        -Purpose '手順書（03-01の手順0）は2つを同じブロックに書いており、どちらかのcwdでは必ず失敗する' `
        -Expect '両方が見つかること。実行場所が別であることを確認する' `
        -Show @"
  src で        : Get-ChildItem app\coupon.py
  EShop直下で   : Get-ChildItem docs

  失敗しても機材の問題ではない。手順書側の不備として11章に記録する。
"@ `
        -Cmd {
            Invoke-InSrc { "src: "; Get-ChildItem 'app\coupon.py' -ErrorAction SilentlyContinue | Select-Object FullName, Length }
            Invoke-InRepo { "EShop直下: "; Get-ChildItem 'docs' -ErrorAction SilentlyContinue | Select-Object Name, Length }
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
            if ($text -notmatch 'クーポン') { Write-Host '  → クーポン件数が出ていない。No3ブランチに切り替わっているか確認する' -ForegroundColor Red }
        }

    New-Step -Id '4-4-05' -Ch '4' -Title '回帰試験の基準線' -Kind auto -TimeKey 'pytest-no3' `
        -Expect '55件PASS' `
        -Show 'pytest' `
        -Cmd { Invoke-InSrc { & (Get-VenvPython) -m pytest 2>&1 } } `
        -Hint {
            param($text)
            if ($text -match '(\d+)\s+passed') {
                $n = [int]$Matches[1]
                if ($n -eq 55) { Write-Host '  → 55件PASS。基準どおり' -ForegroundColor Magenta }
                else { Write-Host "  → $n 件PASS。基準の55件と違う" -ForegroundColor Red }
            }
        }

    New-Step -Id '4-5' -Ch '4' -Title 'Swagger UIでの注文確定（手動）' -Kind manual `
        -Purpose 'pytest は別DBを使うため、ecommerce.db の削除漏れはここでしか表面化しない' `
        -Show @"
  1. src で uvicorn app.main:app --reload を起動し、http://127.0.0.1:8000/docs を開く
  2. POST /auth/login を実行し、access_token を控える
     （ログイン情報は src/app/seed.py に定義されている。README.md には無い）
  3. 画面右上の Authorize にトークンを貼る
  4. POST /cart/items で商品を1件カートに追加する
  5. POST /orders を実行する

  500 で table orders has no column named coupon_code が出たら、
  4-4-04 のDB削除ができていない。DBを消して seed からやり直す。
"@ `
        -Expect 'POST /orders が 201 を返す'

    New-Step -Id '4-4-06' -Ch '4' -Title '生成したテストの実行（手動）' -Kind manual `
        -Show @"
  03-02 の手順で AI に tests/test_coupon.py を生成させ、次を実行する:
    pytest tests/test_coupon.py -v --disable-warnings
"@ `
        -Expect 'テストが実行できること（FAILEDは想定内）'

    New-Step -Id '4-4-07' -Ch '4' -Title 'デバッグ演習の実行（手動）' -Kind manual `
        -Show @"
  03-03 の手順で次を実行する:
    .venv\Scripts\pytest.exe --tb=no -q -rf --disable-warnings

  配布コードには意図的な欠陥が4件仕込んである。失敗が出るのが正常。
  最後に引数なしの pytest が全件PASSする状態まで到達できるかを見る。
"@ `
        -Expect '欠陥4件に由来する失敗が出て、最後に全件PASSまで到達できる'

    # ====================== 5章 Claude Codeの動作確認 ======================

    New-Step -Id '5-1' -Ch '5' -Title '版の記録' -Kind auto `
        -Expect '4-3-02と同じ版であること' `
        -Cmd { claude --version }

    New-Step -Id '5-2' -Ch '5' -Title 'CLAUDE.mdの認識（手動）' -Kind manual `
        -Show "  claude の対話中に /clear のあと /context" `
        -Expect 'Memory files に EShop\CLAUDE.md が出る'

    New-Step -Id '5-3' -Ch '5' -Title 'ルール適用前に .env が出力されるか（手動）' -Kind manual `
        -Purpose 'ここで値が表示されないと01-03の演習前半が成立しない。最重要の確認項目' `
        -Show '  01-03-システムプロンプト設定手順.md の手順1を実施する' `
        -Expect 'ダミーの値がそのまま表示される（表示されない場合は手順書をデモ形式に切り替える判断が必要）'

    New-Step -Id '5-4' -Ch '5' -Title 'ルール適用後に出力されないか（手動）' -Kind manual `
        -Show '  01-03 の手順4を実施する' `
        -Expect 'CLAUDE.md を理由に値を出さない'

    New-Step -Id '5-5' -Ch '5' -Title 'ファイル参照（手動）' -Kind manual `
        -Show '  プロンプトに @docs/要件整理メモ.md を渡す（4-4-01で配置したもの）' `
        -Expect '内容を読み込む'

    New-Step -Id '5-6' -Ch '5' -Title 'ファイル作成の権限プロンプト（手動）' -Kind manual `
        -Show '  03-02 でテストコードを保存させる' `
        -Expect '許可を求められる。受講者への案内を統一する'

    New-Step -Id '5-7' -Ch '5' -Title 'コマンド実行の権限プロンプト（手動）' -Kind manual `
        -Show '  03-03 で .venv\Scripts\pytest.exe を実行させる' `
        -Expect '許可を求められる'

    New-Step -Id '5-8' -Ch '5' -Title 'VS Code拡張でも同じか（手動）' -Kind manual `
        -Show '  5-3〜5-7 と同じ操作を拡張の右パネルで行う' `
        -Expect 'CLIと同じ結果'

    New-Step -Id '5-9' -Ch '5' -Title '.envの抽象化後にアプリが動くか' -Kind manual `
        -Show @"
  01-04-機密情報の抽象化手順.md の手順3を実施したあと、src で pytest を実行する。
  （このスクリプトの 4-3-11 と同じコマンド）
"@ `
        -Expect '全件PASS。DATABASE_URL は置換しない'

    # ====================== 6章 所要時間 ======================

    New-Step -Id '6' -Ch '6' -Title '所要時間の集計' -Kind info `
        -Purpose '4章で計測した値を、カリキュラムの枠と突き合わせる' `
        -Show '実行時に集計表を表示する'

    # ====================== 7章 原状復帰 ======================

    New-Step -Id '7-1' -Ch '7' -Title 'リポジトリに差分が残っていないか' -Kind auto `
        -Purpose '抽象化済みの .env が共有リポジトリに入ると以降の受講者の演習が成立しない' `
        -Expect '.env / .gitignore / CLAUDE.md に差分が無く、未pushのコミットも無い' `
        -Show 'git status ; git diff -- .env .gitignore ; git log origin/main..HEAD ; git remote -v' `
        -Cmd {
            Invoke-InRepo {
                '--- git status ---'; git status 2>&1
                '--- git diff -- .env .gitignore ---'; git diff -- .env .gitignore 2>&1
                '--- git log origin/main..HEAD ---'; git log origin/main..HEAD --oneline 2>&1
                '--- git remote -v ---'; git remote -v 2>&1
            }
        } `
        -Hint {
            param($text)
            Write-Host '  → リハーサル機からは絶対にpushしない。差分は破棄するか、クローンごと削除する（7-3-a）' -ForegroundColor Magenta
        }

    New-Step -Id '7-2-a' -Ch '7' -Title '認証情報のログアウト（手動）' -Kind manual `
        -Show @"
  1. claude の対話中に /logout
     設定ごと消す場合: Remove-Item -Recurse -Force "`$env:USERPROFILE\.claude"
  2. VS Code の Claude Code パネルからサインアウト
  3. ブラウザで claude.ai からログアウト（必要ならプロファイルを削除）
"@ `
        -Expect '3つすべてで講師のアカウント情報が残らないこと'

    New-Step -Id '7-2-b' -Ch '7' -Title '設定した環境変数を消す' -Kind change `
        -Purpose 'setx では消せない。ケースAと判定した場合でも、試したなら消す' `
        -Expect '5つの環境変数が未設定に戻る' `
        -Show @"
  'HTTP_PROXY','HTTPS_PROXY','NO_PROXY','PIP_CERT','NODE_EXTRA_CA_CERTS' |
    ForEach-Object { [Environment]::SetEnvironmentVariable(`$_, `$null, 'User') }
"@ `
        -Cmd {
            'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'PIP_CERT', 'NODE_EXTRA_CA_CERTS' |
                ForEach-Object {
                    [Environment]::SetEnvironmentVariable($_, $null, 'User')
                    "{0} => {1}" -f $_, ([Environment]::GetEnvironmentVariable($_, 'User'))
                }
        }

    New-Step -Id '7-2-c' -Ch '7' -Title 'gitの証明書設定を戻す' -Kind change `
        -Purpose '付録Cで http.sslBackend を設定した場合のみ' `
        -Expect '設定が消えること（設定していなければエラーになるが問題ない）' `
        -Show 'git config --global --unset http.sslBackend' `
        -Cmd {
            git config --global --unset http.sslBackend 2>&1
            "現在の値: $(git config --global --get http.sslBackend 2>&1)"
        }

    New-Step -Id '7-2-d' -Ch '7' -Title '実行ポリシーを戻す（手動）' -Kind manual `
        -Show @"
  Get-ExecutionPolicy -List で確認し、CurrentUser を変えたなら Undefined に戻す:
    Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope CurrentUser
"@ `
        -Expect 'CurrentUser が実施前の値に戻る'

    New-Step -Id '7-3-a' -Ch '7' -Title '作業物を消す' -Kind change `
        -Purpose '記録の退避が済んでから実行する' `
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

    New-Step -Id '7-3-b' -Ch '7' -Title '記録の退避' -Kind info `
        -Purpose '記録票と許可申請の根拠になる。機材から消す前に持ち帰る' `
        -Show '実行時に保存先を表示する'
}

# ---------------------------------------------------------------- 実行

function Show-Step($Step, [int]$Index, [int]$Total) {
    $kindLabel = switch ($Step.Kind) {
        'auto'   { '<読み取り / 実行>' }
        'change' { '<設定変更>' }
        'manual' { '<手動操作>' }
        'ask'    { '<聞き取り>' }
        'info'   { '<確認のみ>' }
    }
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
    Write-Host ("  所要 {0} 秒" -f $sec) -ForegroundColor DarkGray
    if ($Step.TimeKey) { $script:Timings[$Step.TimeKey] = $sec }
    $text = ($raw | Out-String -Width 200)
    $script:Captured[$Step.Id] = $text
    if ($Step.Hint) {
        try { & $Step.Hint $text } catch { }
    }
    return @{ Text = $text; Seconds = $sec }
}

function Read-Verdict($Step, [string]$Output, [double]$Seconds) {
    $memo = ''
    while ($true) {
        $ans = Read-Key '判定  [Enter]=OK   [n]=NG   [h]=保留   [m]=メモを書く   [q]=保留にして中断'
        switch ($ans.ToLower()) {
            ''  { Add-Result $Step 'OK'   $Output $memo $Seconds; Write-Host '  OK として記録' -ForegroundColor Green;  return }
            'n' { Add-Result $Step 'NG'   $Output $memo $Seconds; Write-Host '  NG として記録' -ForegroundColor Red;    return }
            'h' { Add-Result $Step '保留' $Output $memo $Seconds; Write-Host '  保留として記録' -ForegroundColor Yellow; return }
            'm' { $memo = Read-Host '  メモ' }
            'q' {
                Add-Result $Step '保留' $Output $memo $Seconds
                $script:Aborted = $true
                Write-Host '  保留として記録し、中断する' -ForegroundColor Yellow
                return
            }
            default { Write-Host '  Enter / n / h / m / q のいずれかを入力する' -ForegroundColor DarkGray }
        }
    }
}

function Show-Timings {
    $rows = @(
        @{ Key = 'clone';       Label = 'git clone';                     Ref = '社内1.2秒' }
        @{ Key = 'venv';        Label = 'python -m venv';                Ref = '社内8.5秒' }
        @{ Key = 'pip';         Label = 'pip install -r requirements';   Ref = '社内31.4秒' }
        @{ Key = 'seed';        Label = 'python -m app.seed（main）';     Ref = '社内1.9秒' }
        @{ Key = 'pytest-main'; Label = 'pytest（54件）';                 Ref = '社内8.6秒' }
        @{ Key = 'fetch';       Label = 'git fetch + switch No3';        Ref = '' }
        @{ Key = 'seed-no3';    Label = 'DB削除 + seed（No3）';           Ref = '' }
        @{ Key = 'pytest-no3';  Label = 'pytest（55件）';                 Ref = '' }
    )
    Write-Host ''
    Write-Host '  6-1 No.1のセットアップ（ハンズオン持ち時間の目安12分）' -ForegroundColor Cyan
    $no1 = 0.0
    foreach ($r in $rows[0..4]) {
        $v = $script:Timings[$r.Key]
        if ($null -ne $v) { $no1 += [double]$v }
        Write-Host ('    {0,-34} {1,8}  {2}' -f $r.Label, $(if ($null -ne $v) { "$v 秒" } else { '未計測' }), $r.Ref)
    }
    Write-Host ('    {0,-34} {1,8}' -f '小計（Claude Code導入を除く）', "$([math]::Round($no1,1)) 秒") -ForegroundColor White
    Write-Host ''
    Write-Host '  6-2 No.3の導入（20分枠）' -ForegroundColor Cyan
    $no3 = 0.0
    foreach ($r in $rows[5..7]) {
        $v = $script:Timings[$r.Key]
        if ($null -ne $v) { $no3 += [double]$v }
        Write-Host ('    {0,-34} {1,8}  {2}' -f $r.Label, $(if ($null -ne $v) { "$v 秒" } else { '未計測' }), $r.Ref)
    }
    Write-Host ('    {0,-34} {1,8}' -f '小計', "$([math]::Round($no3,1)) 秒") -ForegroundColor White
    Write-Host ''
    Write-Host '  Claude Codeの導入・ログイン・VS Code拡張は手動ステップのため、時計で測って記録票に書く' -ForegroundColor DarkGray
}

function Save-Record {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path $script:OutRoot "precheck-result-$stamp.md"
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("# 事前確認書 第I部 実施記録")
    $null = $sb.AppendLine()
    $null = $sb.AppendLine("- 実施日時: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    $null = $sb.AppendLine("- 機材: $env:COMPUTERNAME")
    $null = $sb.AppendLine("- 実施者: $env:USERNAME")
    $null = $sb.AppendLine("- 作業フォルダ: $script:WorkRoot")
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('## 判定一覧')
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('| 章 | 項目 | 判定 | 所要 | メモ |')
    $null = $sb.AppendLine('| :-- | :-- | :-- | --: | :-- |')
    foreach ($r in $script:Results) {
        $secText = if ($r.Seconds -ge 0) { "$($r.Seconds)秒" } else { '' }
        $memo = ($r.Memo -replace '\|', '\|') -replace "`r?`n", ' '
        $null = $sb.AppendLine("| $($r.Ch) | $($r.Id) $($r.Title) | $($r.Verdict) | $secText | $memo |")
    }
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('## 所要時間（6章）')
    $null = $sb.AppendLine()
    foreach ($k in $script:Timings.Keys | Sort-Object) {
        $null = $sb.AppendLine("- $k : $($script:Timings[$k]) 秒")
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

# ---------------------------------------------------------------- 起点

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host 'PowerShell 5.1 以上で実行する' -ForegroundColor Red
    return
}

$desktop = [Environment]::GetFolderPath('Desktop')
$script:WorkRoot = if ($WorkDir) { $WorkDir } else { Join-Path $desktop 'rehearsal' }
$script:RepoDir = Join-Path $script:WorkRoot 'EShop'
$script:SrcDir = Join-Path $script:RepoDir 'src'
$script:OutRoot = if ($OutDir) { $OutDir } else { $desktop }
$script:MaterialRoot = if ($MaterialDir) { $MaterialDir } elseif ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$script:ChangedEnv = $false

Set-StepList

$targetChapters = if ($Chapter) { $Chapter | ForEach-Object { "$_" } } else { @('2', '3', '4', '5', '6', '7') }
$steps = $script:Steps | Where-Object { $targetChapters -contains $_.Ch }
$total = @($steps).Count

Write-Head ' 事前確認書 第I部（実機確認）'
Write-Host @"
  1ステップずつコマンドを表示し、Enterで実行して結果を表示する。
  判定とメモをその場で入力し、最後に記録をファイルへ書き出す。

  管理者権限は不要。<設定変更> と表示されるステップだけが機材の状態を変え、
  既定はスキップ、y を押したときだけ実行する（すべて7章で元へ戻す）。

  対象章       : $($targetChapters -join ', ')  （全 $total ステップ）
  作業フォルダ : $script:WorkRoot
  テンプレート : $script:MaterialRoot\docs-template
  記録の出力先 : $script:OutRoot
"@ -ForegroundColor Gray

try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Host ''
        Write-Host '  この端末は管理者として実行されている。受講者と同じ権限で実施するため、' -ForegroundColor Red
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
    Write-Host " 下見おわり（$total ステップ）" -ForegroundColor Cyan
    Write-Rule '='
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

$null = Read-Key '準備ができたら [Enter] で開始する（[q]=中断）'

$index = 0
foreach ($step in $steps) {
    $index++
    if ($script:Aborted) { break }

    if ($step.When) {
        $ok = $false
        try { $ok = [bool](& $step.When) } catch { $ok = $false }
        if (-not $ok) {
            Show-Step $step $index $total
            Write-Host ''
            Write-Host '  条件に当たらないため自動スキップした' -ForegroundColor DarkGray
            Add-Result $step '該当なし' '' '条件に当たらないため自動スキップ'
            continue
        }
    }

    Show-Step $step $index $total

    # ---- info ステップ
    if ($step.Kind -eq 'info') {
        switch ($step.Id) {
            '4-0' {
                Write-Host ''
                Write-Label '作業' $script:WorkRoot 'White'
                Write-Label 'テンプレ' (Join-Path $script:MaterialRoot 'docs-template') 'White'
                Write-Host '  ここから先はファイルを作る。場所を変える場合は中断して -WorkDir で指定し直す' -ForegroundColor DarkGray
                Write-Host ''
                Write-Host '  4章の前提' -ForegroundColor Cyan
                foreach ($c in 'git', 'python') {
                    $cmd = Get-Command $c -ErrorAction SilentlyContinue
                    if ($cmd) { Write-Host ("    {0,-8} {1}" -f $c, $cmd.Source) -ForegroundColor Green }
                    else { Write-Host ("    {0,-8} 見つからない" -f $c) -ForegroundColor Red }
                }
                $tpl = Join-Path $script:MaterialRoot 'docs-template'
                $n = @(Get-ChildItem (Join-Path $tpl '*.md') -ErrorAction SilentlyContinue).Count
                if ($n -gt 0) { Write-Host ("    {0,-8} {1} （{2}件）" -f 'テンプレ', $tpl, $n) -ForegroundColor Green }
                else { Write-Host ("    {0,-8} 見つからない（4-4-01で必要。-MaterialDir で指定する）" -f 'テンプレ') -ForegroundColor Red }
            }
            '6'   { Show-Timings }
            '7-3-b' {
                Write-Host ''
                Write-Host "  Start-Transcript の記録: $(Join-Path $script:OutRoot 'rehearsal-check.txt')" -ForegroundColor White
                Write-Host '  この記録と、最後に出力される precheck-result-*.md を講師の環境へ持ち帰る' -ForegroundColor White
                Write-Host ''
                Write-Host '  持ち帰ったあとに、機材に残した次のファイルを消す（講師専用資料を残さない）' -ForegroundColor Cyan
                Write-Host ("    {0}" -f (Join-Path $script:OutRoot 'rehearsal-check.txt')) -ForegroundColor White
                Write-Host ("    {0}" -f (Join-Path $script:OutRoot 'precheck-result-*.md')) -ForegroundColor White
                Write-Host ("    {0}  （rehearsalブランチのクローンごと）" -f $script:MaterialRoot) -ForegroundColor White
                Write-Host '  この削除は自動では行わない（講師自身のPCで実行した場合に本体を消してしまうため）' -ForegroundColor DarkGray
            }
        }
        $ans = Read-Key '[Enter]=確認した   [q]=中断'
        if ($ans.ToLower() -eq 'q') { $script:Aborted = $true; break }
        Add-Result $step '確認' '' ''
        continue
    }

    # ---- ask ステップ
    if ($step.Kind -eq 'ask') {
        $ans = Read-Key '回答を入力（[q]=中断   Enterのみ=スキップ）'
        if ($ans.ToLower() -eq 'q') { $script:Aborted = $true; break }
        if (-not $ans) {
            Add-Result $step 'スキップ' '' ''
            Write-Host '  スキップとして記録' -ForegroundColor DarkGray
            continue
        }
        Add-Result $step '記録' $ans ''
        Write-Host "  記録した: $ans" -ForegroundColor Green

        # 3-4-3 だけは入力されたURLの到達性も測る
        if ($step.Id -eq '3-4-3' -and $ans -match '^https?://') {
            Write-Rule
            $code = (curl.exe -s -o NUL -w "%{http_code}" --max-time 20 $ans 2>&1)
            Write-Host "  $ans => $code" -ForegroundColor White
            Write-Rule
            $script:Captured['3-4-3'] = "$ans => $code"
            $script:Results[-1].Output = "$ans => $code"
        }
        continue
    }

    # ---- manual ステップ
    if ($step.Kind -eq 'manual') {
        $ans = Read-Key '[Enter]=実施した   [s]=スキップ   [q]=中断'
        if ($ans.ToLower() -eq 'q') { $script:Aborted = $true; break }
        if ($ans.ToLower() -eq 's') {
            Add-Result $step 'スキップ' '' ''
            Write-Host '  スキップとして記録' -ForegroundColor DarkGray
            continue
        }
        $obs = Read-Host '  観測した結果（画面に出た内容・エラー文面。無ければEnter）'
        Read-Verdict $step $obs -1
        continue
    }

    # ---- change ステップ（既定はスキップ）
    if ($step.Kind -eq 'change') {
        Write-Host ''
        Write-Host '  このステップは機材の状態を変える。7章で元へ戻す対象になる' -ForegroundColor Red
        $ans = Read-Key '[y]=実行する   [Enter]=スキップ（既定）   [q]=中断'
        if ($ans.ToLower() -eq 'q') { $script:Aborted = $true; break }
        if ($ans.ToLower() -ne 'y') {
            Add-Result $step 'スキップ' '' '設定変更のため実行しなかった'
            Write-Host '  スキップとして記録' -ForegroundColor DarkGray
            continue
        }
        $r = Invoke-Step $step
        Read-Verdict $step $r.Text $r.Seconds
        continue
    }

    # ---- auto ステップ
    $ans = Read-Key '[Enter]=実行   [s]=スキップ   [q]=中断'
    if ($ans.ToLower() -eq 'q') { $script:Aborted = $true; break }
    if ($ans.ToLower() -eq 's') {
        Add-Result $step 'スキップ' '' ''
        Write-Host '  スキップとして記録' -ForegroundColor DarkGray
        continue
    }
    $r = Invoke-Step $step
    Read-Verdict $step $r.Text $r.Seconds
}

# ---------------------------------------------------------------- まとめ

Write-Head ' 実施結果'

if ($script:Results.Count -eq 0) {
    Write-Host '  記録はない' -ForegroundColor DarkGray
} else {
    foreach ($r in $script:Results) {
        $c = switch ($r.Verdict) {
            'OK'   { 'Green' }
            'NG'   { 'Red' }
            '保留' { 'Yellow' }
            default { 'DarkGray' }
        }
        Write-Host ('  {0,-6} {1,-10} {2}' -f $r.Verdict, $r.Id, $r.Title) -ForegroundColor $c
    }
    Write-Host ''
    $ng = @($script:Results | Where-Object Verdict -eq 'NG')
    $hold = @($script:Results | Where-Object Verdict -eq '保留')
    Write-Host ("  OK {0} / NG {1} / 保留 {2} / その他 {3}" -f `
        @($script:Results | Where-Object Verdict -eq 'OK').Count, $ng.Count, $hold.Count,
        @($script:Results | Where-Object { $_.Verdict -notin 'OK', 'NG', '保留' }).Count) -ForegroundColor White
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

if ($script:ChangedEnv) {
    Write-Host ''
    Write-Host '  このセッションでプロキシの環境変数を設定した。7-2-bで削除すること' -ForegroundColor Red
}

try {
    $saved = Save-Record
    Write-Host ''
    Write-Host "  記録を書き出した: $saved" -ForegroundColor Green
} catch {
    Write-Host ''
    Write-Host "  記録の書き出しに失敗した: $($_.Exception.Message)" -ForegroundColor Red
}

if (-not $NoTranscript) {
    try { Stop-Transcript | Out-Null } catch { }
}

Write-Host ''
Write-Host '  記録は機材から消す前に講師の環境へ持ち帰る（7-3）' -ForegroundColor White
Write-Host ''
