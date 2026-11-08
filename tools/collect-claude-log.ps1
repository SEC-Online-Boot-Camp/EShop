<#
    Claude Code に接続できない・応答が遅いときの調査用に、ログから関係する行だけを集めて、1つのテキストファイルにする

    集めるもの：PCとツールの版、最後に起動した時刻、ログインの種類（Login method の行だけ）、
    VS Code 拡張のログと Claude Code のデバッグログのうち、接続の失敗に関係する行。
    読み取りだけで、設定は何も変えない。ネットワークにはつながない（アップロードはしない）。
    会話の中身と、証明書ストアの情報は集めない。メールアドレス・IPアドレス（IPv4・IPv6）・
    Anthropic 以外のホスト名（https:// の無いものも）・トークン・Windows のユーザー名は伏せる。
    伏せ方は文字の形で決めているので、漏れることがある。出す前に中身を確かめる。
    デスクトップに「claude-diag-<日時>.txt」を作る。受講者は中身を確かめてから、提出先の自分のフォルダへアップロードする。

    -Connections を付けると、いま開いている TCP 接続の数を、プロセスごと・状態ごとに数えて足す
    （接続先のアドレスは記録しない）。接続の一覧を読むので、講師の指示があるときだけ付ける。

    起動方法（EShop のフォルダを開いた VS Code のターミナルで、EShop のルートから。上から順に試す）

        1) 通常
           .\tools\collect-claude-log.ps1
           .\tools\collect-claude-log.ps1 -Connections     （講師の指示があるときだけ）

        2) 「このシステムではスクリプトの実行が無効になっている」と出る場合
           powershell -ExecutionPolicy Bypass -File .\tools\collect-claude-log.ps1

        2でも同じエラーになる場合は、講師に申し出る。
#>
param(
    [int]$Days = 2,          # 何日前までのログを見るか
    [switch]$Connections     # TCP 接続の数をプロセスごとに数える（講師の指示があるときだけ）
)

$ErrorActionPreference = 'Continue'
$since = (Get-Date).AddDays(-$Days)
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$outFile = Join-Path ([Environment]::GetFolderPath('Desktop')) "claude-diag-$stamp.txt"
$lines = New-Object System.Collections.Generic.List[string]
$userPattern = '(?i)(?<![A-Za-z0-9])' + [regex]::Escape($env:USERNAME) + '(?![A-Za-z0-9])'

function Hide-Sensitive([string]$s) {
    $s = [regex]::Replace($s, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '<email>')
    # IPv6 は、「::」を含むか区切りが5つ以上のものだけを伏せる（時刻の 12:34:56 を残すため）
    $s = [regex]::Replace($s, '(?<![0-9A-Za-z:])[0-9A-Fa-f]{0,4}(:[0-9A-Fa-f]{0,4}){2,7}(?![0-9A-Za-z:])', {
            param($m)
            $v = $m.Value
            if ($v.Contains('::') -or ($v.Split(':').Count -ge 6)) { '<ip>' } else { $v }
        })
    $s = [regex]::Replace($s, '\b\d{1,3}(\.\d{1,3}){3}\b', '<ip>')
    $s = [regex]::Replace($s, '(?i)(bearer\s+|sk-ant-|token["'':=\s]+)[A-Za-z0-9._\-]+', '$1<hidden>')
    $s = [regex]::Replace($s, '(?i)https?://([A-Za-z0-9.-]+)', {
            param($m)
            $h = $m.Groups[1].Value
            if ($h -match '(^|\.)(anthropic\.com|claude\.ai|claude\.com)$') { $m.Value } else { 'http://<host>' }
        })
    # https:// の無いホスト名（ENOTFOUND の後など）も伏せる。ファイル名（.log・.js など）は残す
    $s = [regex]::Replace($s, '(?<![A-Za-z0-9_.@/<-])[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}(?![A-Za-z0-9_-])', {
            param($m)
            $h = $m.Value
            if ($h -match '(?i)(^|\.)(anthropic\.com|claude\.ai|claude\.com)$') { return $h }
            if ($h -match '(?i)\.(log|txt|md|json|jsonl|js|cjs|mjs|ts|map|node|exe|dll|ps1|py|html|css|yaml|yml|toml|lock|vsix|zip)$') { return $h }
            '<host>'
        })
    # ユーザー名は、パスの区切りが何であっても伏せる
    $s = [regex]::Replace($s, $userPattern, '<user>')
    return $s
}

function Add([string]$s) { $lines.Add((Hide-Sensitive $s)) }

$pattern = 'Remote settings|Policy limits|Unable to connect|Failed to connect|fetch failed|first-byte|EADDRINUSE|ETIMEDOUT|ECONNRESET|ECONNREFUSED|ENOTFOUND|UNABLE_TO_|SELF_SIGNED|CERT_HAS_EXPIRED|\[error\]|\[ERROR\]'
# 画面とのやり取りの行には会話の中身が入ることがある。証明書ストアの行は集めない
$exclude = 'CA certs|mTLS|webview|"type":"(request|response)"|prompt|content'

Add "# Claude Code 接続調査ログ"
Add "作成日時: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Add "対象期間: $($since.ToString('yyyy-MM-dd HH:mm')) 以降"
Add ""

# 1. PCとツールの版
Add "## 1. PCとツールの版"
try {
    $os = Get-CimInstance Win32_OperatingSystem
    Add "Windows: $($os.Caption) $($os.Version)"
    Add "最後に起動した時刻: $($os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss'))"
} catch { Add "Windows: 取得できず" }
try { Add "claude --version: $((& claude --version 2>&1 | Out-String).Trim())" } catch { Add "claude --version: 実行できず" }
$ext = Get-ChildItem "$HOME\.vscode\extensions" -Directory -Filter 'anthropic.claude-code-*' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
Add "VS Code拡張: $(if ($ext) { $ext.Name } else { '見つからず' })"
try {
    $auth = (& claude auth status --text 2>&1 | Out-String)
    $method = ($auth -split "`r?`n" | Where-Object { $_ -match '^\s*Login method' }) -join ''
    Add "ログイン: $(if ($method) { $method.Trim() } else { '「Login method」の行なし' })"
} catch { Add "ログイン: 確かめられず" }
$claudeProcs = @(Get-Process -Name claude -ErrorAction SilentlyContinue)
Add "動いている claude のプロセス: $($claudeProcs.Count) 個"
Add ""

function Add-Hits($file, [int]$max) {
    $hit = Select-String -Path $file.FullName -Pattern $pattern -ErrorAction SilentlyContinue |
        Where-Object { $_.Line -notmatch $exclude }
    if (-not $hit) { Add "（該当なし）"; return }
    $hit | Select-Object -Last $max | ForEach-Object { Add $_.Line.Substring(0, [Math]::Min(300, $_.Line.Length)) }
}

# 2. VS Code拡張のログ（Claude VSCode.log）から関係する行
Add "## 2. VS Code拡張のログ（関係する行だけ）"
$vsLogs = Get-ChildItem "$env:APPDATA\Code\logs" -Recurse -Filter 'Claude VSCode.log' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $since } | Sort-Object LastWriteTime
if (-not $vsLogs) { Add "（対象期間のログなし）" }
foreach ($f in $vsLogs) {
    Add "### $($f.Directory.Parent.Parent.Parent.Name)\$($f.Directory.Parent.Parent.Name)  (更新: $($f.LastWriteTime.ToString('MM-dd HH:mm')))"
    Add-Hits $f 200
}
Add ""

# 3. Claude Code のデバッグログ（~\.claude\debug）から関係する行
Add "## 3. Claude Codeのデバッグログ（関係する行だけ）"
$dbg = Get-ChildItem "$HOME\.claude\debug" -Filter '*.txt' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $since } | Sort-Object LastWriteTime
if (-not $dbg) { Add "（対象期間のログなし）" }
foreach ($f in $dbg) {
    Add "### $($f.Name)  (更新: $($f.LastWriteTime.ToString('MM-dd HH:mm')))"
    Add-Hits $f 100
}

# 4. TCP 接続の数（-Connections を付けたときだけ。接続先のアドレスは記録しない）
if ($Connections) {
    Add ""
    Add "## 4. TCP接続の数（プロセスごと・多い順に10個）"
    try {
        $conns = @(Get-NetTCPConnection -ErrorAction Stop)
        Add "合計: $($conns.Count) 件（状態ごと: $(($conns | Group-Object State | Sort-Object Count -Descending | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', ')）"
        $range = (Get-NetTCPSetting -SettingName Internet -ErrorAction SilentlyContinue)
        if ($range) { Add "動的ポートの範囲: $($range.DynamicPortRangeStartPort) から $($range.DynamicPortRangeNumberOfPorts) 個" }
        $conns | Group-Object OwningProcess | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
            $p = Get-Process -Id ([int]$_.Name) -ErrorAction SilentlyContinue
            $states = ($_.Group | Group-Object State | Sort-Object Count -Descending | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '
            Add ("{0,6} 件  {1}  ({2})" -f $_.Count, $(if ($p) { $p.ProcessName } else { "PID $($_.Name)" }), $states)
        }
    } catch { Add "（数えられず: $($_.Exception.Message)）" }
}

$lines | Set-Content -Path $outFile -Encoding UTF8
Write-Host ""
Write-Host "できました: $outFile" -ForegroundColor Green
Write-Host "中身を開いて、見せたくないものが無いかを確かめてから、提出先の自分のフォルダにアップロードしてください。"
