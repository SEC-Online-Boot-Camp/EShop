<#
    総合演習（No.4）の提出物を、1つのzipにまとめる

    EShop のフォルダを丸ごと（.git を含む）と、Claude Code の会話の記録（EShop で使った分）を、
    デスクトップの「提出_<氏名>_<日時>.zip」にまとめる。提出に要るファイルがあるかも確かめる。
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
    'docs/問い合わせ記録.md',
    'docs/基本設計書.md',
    'docs/試験観点シート.md',
    'docs/総合演習-プロンプト記録.md',
    'docs/総合演習-振り返り.md',
    'CLAUDE.md',
    'backend/tests/integration/test_order_cancel.py'
)
# zip に入れないフォルダ（名前で判定する）とファイル（パターン）
$skipDirs  = @('.venv', 'venv', '__pycache__', '.pytest_cache', 'node_modules', '.mutmut-cache', 'htmlcov')
$skipFiles = @('*.db', '*.pyc', '.coverage')

# 1. EShop のルートを確かめる
$root = "$(& git rev-parse --show-toplevel 2>$null)".Trim()
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

# 3. zip の名前（氏名は 01-01 で設定した git の名前）
$name = "$(& git -C $root config user.name 2>$null)".Trim()
if (-not $name) { $name = $env:USERNAME }
foreach ($c in [IO.Path]::GetInvalidFileNameChars()) { $name = $name.Replace([string]$c, '_') }
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$desktop = [Environment]::GetFolderPath('Desktop')
$zipPath = Join-Path $desktop "提出_${name}_${stamp}.zip"

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

# 4. zip を作る
$zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    $n = Add-Tree $zip $root 'EShop'
    Write-Host ''
    Write-Host "EShop のファイル: $n 件（.venv・__pycache__・DB などは入れていない）"

    # Claude Code の会話の記録（EShop で使った分）
    $config = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
    $projects = Join-Path $config 'projects'
    $sessions = 0
    $encoded = $root -replace '[^A-Za-z0-9]', '-'
    if (Test-Path $projects) {
        foreach ($d in Get-ChildItem -LiteralPath $projects -Directory -Force) {
            # 記録のフォルダ名は、作業フォルダのパスの英数字以外を「-」にしたもの（例：C--Users-yamada-EShop）。
            # EShop と、その下のフォルダ（backend など）で使った分だけを集める
            if ($d.Name -ieq $encoded -or $d.Name.StartsWith("$encoded-", [StringComparison]::OrdinalIgnoreCase)) {
                $sessions += Add-Tree $zip $d.FullName "claude-sessions/$($d.Name)"
            }
        }
    }
    Write-Host "Claude Code の会話の記録: $sessions 件"
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

