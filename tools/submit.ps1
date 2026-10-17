<#
    総合演習（No.4）の提出物を、1つのzipにまとめる

    EShop のフォルダを丸ごと（.git を含む）と、Claude Code の会話の記録（EShop で使った分のうち、
    04-01 の「No.4 start」のコミットより後の部分）を、
    デスクトップの「提出_<日時>.zip」にまとめる。提出に要るファイルがあるかも確かめる。
    読み取りだけで、EShop の中のファイルは変えない。ネットワークにはつながない（アップロードはしない）。
    作った zip は、受講者が提出先の自分のフォルダへ、ブラウザでアップロードする。

    起動方法（EShop のフォルダを開いた VS Code のターミナルで、EShop のルートから。上から順に試す）

        1) 通常
           .\tools\submit.ps1

        2) 「このシステムではスクリプトの実行が無効になっている」と出る場合
           powershell -ExecutionPolicy Bypass -File .\tools\submit.ps1

        3) 2でも同じエラーになる場合（グループポリシーで縛られているPC）
           & ([scriptblock]::Create((Get-Content .\tools\submit.ps1 -Raw -Encoding UTF8)))
#>

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# 提出に要るファイル（EShop のルートからの相対パス）
$required = @(
    'docs/要件整理-注文キャンセル.md',
    'docs/基本設計書.md',
    'docs/試験観点シート.md',
    'CLAUDE.md',
    'backend/tests/integration/test_order_cancel.py'
)
# zip に入れないフォルダ（名前で判定する）とファイル（パターン）
$skipDirs  = @('.venv', 'venv', '__pycache__', '.pytest_cache', 'node_modules', '.mutmut-cache', 'htmlcov')
$skipFiles = @('*.db', '*.pyc', '.coverage')

# git は出力を UTF-8 で返すが、PowerShell は外部コマンドの出力を [Console]::OutputEncoding
# （日本語の Windows では Shift-JIS）で読むため、日本語のパスが化ける。
# git を呼ぶ間だけ UTF-8 にして、終わったら元に戻す。
function Invoke-GitUtf8 {
    $prevOutEnc = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        & git @args 2>$null
    }
    finally {
        [Console]::OutputEncoding = $prevOutEnc
    }
}

# 1. EShop のルートを確かめる
$root = "$(Invoke-GitUtf8 rev-parse --show-toplevel)".Trim()
if (-not $root -or -not (Test-Path (Join-Path $root 'backend'))) {
    Write-Host 'EShop のフォルダで実行してください（cd $HOME\EShop）。' -ForegroundColor Red
    return
}
$root = (Resolve-Path $root).Path
Write-Host "EShop: $root"

# 2. 提出に要るファイルを確かめる
Write-Host ''
Write-Host '--- 提出に要るファイル ---'
$missing = @()
foreach ($r in $required) {
    if (Test-Path -LiteralPath (Join-Path $root ($r -replace '/', '\'))) {
        Write-Host "  あり  $r"
    } else {
        Write-Host "  なし  $r" -ForegroundColor Yellow
        $missing += $r
    }
}

# 3. zip の名前（提出先の各自のフォルダに置くので、名前は入れない）
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$desktop = [Environment]::GetFolderPath('Desktop')
$zipPath = Join-Path $desktop "提出_${stamp}.zip"

function Test-Skip([IO.FileSystemInfo]$item) {
    if ($item.PSIsContainer) { return $skipDirs -contains $item.Name }
    foreach ($p in $skipFiles) { if ($item.Name -like $p) { return $true } }
    return $false
}

function Add-Tree($zip, [string]$dir, [string]$prefix) {
    $count = 0
    foreach ($item in Get-ChildItem -LiteralPath $dir -Force) {
        if (Test-Skip $item) { continue }
        $entry = if ($prefix) { "$prefix/$($item.Name)" } else { $item.Name }
        if ($item.PSIsContainer) {
            $count += Add-Tree $zip $item.FullName $entry
        } else {
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $item.FullName, $entry)
            $count++
        }
    }
    return $count
}

# 4. zip を作る（同じ名前の zip があれば、上書きする）
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
$zip =[IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    $n = Add-Tree $zip $root 'EShop'
    Write-Host ''
    Write-Host "EShop のファイル: $n 件（.venv・__pycache__・DB などは入れていない）"

    # Claude Code の会話の記録（EShop で使った分のうち、No.4 の開始より後の部分）
    $config = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
    $projects = Join-Path $config 'projects'
    $sessions = 0
    $encoded = $root -replace '[^A-Za-z0-9]', '-'

    # No.4 の開始時点は、04-01 で作る「No.4 start」のコミットの時刻とする
    $startText = "$(Invoke-GitUtf8 -C $root log -1 --format=%cI '--grep=^No\.4 start$')".Trim()
    $start = $null
    if ($startText) {
        $start = [DateTimeOffset]::Parse($startText, [Globalization.CultureInfo]::InvariantCulture)
        Write-Host "会話の記録は、No.4 の開始（$($start.ToLocalTime().ToString('yyyy-MM-dd HH:mm'))）より後の部分だけを入れる"
    } else {
        Write-Host '「No.4 start」のコミットが見つからないので、会話の記録をすべて入れる' -ForegroundColor Yellow
    }

    function Get-LineTime($line) {
        # 1行が1つのJSON。時刻（timestamp）が無い行は $null を返す
        try { $j = $line | ConvertFrom-Json } catch { return $null }
        $p = $j.PSObject.Properties['timestamp']
        if (-not $p -or -not $p.Value) { return $null }
        $v = $p.Value
        if ($v -is [datetime]) {
            # PowerShell 7 は日時の型に変えて返す
            if ($v.Kind -eq [DateTimeKind]::Unspecified) { $v = [datetime]::SpecifyKind($v, [DateTimeKind]::Utc) }
            return [DateTimeOffset]$v.ToUniversalTime()
        }
        return [DateTimeOffset]::Parse([string]$v, [Globalization.CultureInfo]::InvariantCulture)
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    if (Test-Path $projects) {
        foreach ($d in Get-ChildItem -LiteralPath $projects -Directory -Force) {
            # 記録のフォルダ名は、作業フォルダのパスの英数字以外を「-」にしたもの（例：C--Users-yamada-EShop）。
            # EShop と、その下のフォルダ（backend など）で使った分だけを集める
            if (-not ($d.Name -ieq $encoded -or $d.Name.StartsWith("$encoded-", [StringComparison]::OrdinalIgnoreCase))) { continue }
            foreach ($f in Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force) {
                $entry = "claude-sessions/$($d.Name)/" + $f.FullName.Substring($d.FullName.Length + 1).Replace('\', '/')
                if (-not $start -or $f.Extension -ne '.jsonl') {
                    if ($start -and $f.LastWriteTime -lt $start.LocalDateTime) { continue }
                    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $entry)
                    $sessions++
                    continue
                }
                # 時刻のある行のうち、No.4 の開始より後のものだけを残す。
                # 時刻の無い行は入れない（過去の依頼文を含む行があり、開始より前の部分が混ざるため）
                $kept = New-Object System.Collections.Generic.List[string]
                foreach ($line in [IO.File]::ReadLines($f.FullName, $utf8)) {
                    if (-not $line) { continue }
                    $t = Get-LineTime $line
                    if ($null -ne $t -and $t -ge $start) { $kept.Add($line) }
                }
                if ($kept.Count -eq 0) { continue }
                $w = New-Object System.IO.StreamWriter($zip.CreateEntry($entry).Open(), $utf8)
                try { foreach ($line in $kept) { $w.Write($line); $w.Write("`n") } }
                finally { $w.Dispose() }
                $sessions++
            }
        }
    }
    Write-Host "Claude Code の会話の記録: $sessions 件"
    if ($sessions -eq 0) {
        Write-Host '会話の記録が0件。EShop のフォルダを開いた VS Code で Claude Code を使ったか確かめる。（使っていないなら、このままでよい）' -ForegroundColor Yellow
    }
}
finally {
    $zip.Dispose()
}

# 5. 結果
$size = [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 1)
Write-Host ''
Write-Host "作成した: $zipPath（$size MB）" -ForegroundColor Green
if ($missing.Count -gt 0) {
    Write-Host "足りないファイルが $($missing.Count) 件ある。手順書を見直し、作ってからもう一度実行する。（このzipは消してよい）" -ForegroundColor Yellow
} else {
    Write-Host '提出に要るファイルはそろっている。'
}
Write-Host '次に、このzipを、提出先の自分のフォルダにアップロードする。'

