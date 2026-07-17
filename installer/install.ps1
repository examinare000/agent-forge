# agent-forge 頒布用インストーラ（Windows / PowerShell 版）。
#
# v1 の制限（意図的なスコープ限定。install.sh との機能差分）:
#   - symlink ではなく copy でインストールする。Windowsのsymlink作成には
#     開発者モード有効化 or 管理者権限が必要で、頒布用インストーラの
#     前提として要求するのは非現実的なため（install.sh側はUNIX symlink前提）。
#     そのため copy 運用では「repo側を更新したら再度 install.ps1 を実行し直す」
#     運用になる（install.sh のような自動追従はしない）。
#   - サポートするのは -Check（存在検査のみ・read-only）と既定のcopyインストール
#     のみ。--force / --uninstall / superpowers clone は v1では未実装。
#     settings.json の初期作成・マージ案内は v1 未実装（copy 運用では hooks が有効化
#     されない。hooks を使う場合は手動で settings.json に配線するか macOS/Linux 版
#     install.sh を使用してください）。
#   - manifest.json は ConvertFrom-Json（PowerShell組込み）で読む。jq依存を
#     Windows側に持ち込まないための選択。
#
# 使い方:
#   pwsh -File installer\install.ps1          # インストール実行（copy）
#   pwsh -File installer\install.ps1 -Check   # doctorモード（read-only）

param(
  [switch]$Check
)

$ErrorActionPreference = "Stop"

$InstallPsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $InstallPsDir

if (-not $env:CLAUDE_DIR -or $env:CLAUDE_DIR -eq "") {
  $ClaudeDir = Join-Path $HOME ".claude"
} else {
  $ClaudeDir = $env:CLAUDE_DIR
}

$ManifestPath = Join-Path $InstallPsDir "manifest.json"
if (-not (Test-Path $ManifestPath)) {
  Write-Error "manifest.json が見つかりません: $ManifestPath"
  exit 1
}
$Manifest = Get-Content -Raw -Path $ManifestPath | ConvertFrom-Json

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

if ($Check) {
  Write-Info "=== doctor（read-only チェック, Windows/copy運用） ==="
  $failCount = 0
  foreach ($entry in $Manifest.linkEntries) {
    $livePath = Join-Path $ClaudeDir $entry.claudePath
    if (Test-Path $livePath) {
      Write-Info "  [OK]   $($entry.name): 存在します（copy運用のためsymlink検査はしない）"
    } else {
      Write-Err "  [FAIL] $($entry.name): 存在しません（$livePath）"
      $failCount++
    }
  }
  foreach ($name in $Manifest.prereqs.required) {
    if (Get-Command $name -ErrorAction SilentlyContinue) {
      Write-Info "  [OK]   必須CLI検出: $name"
    } else {
      Write-Err "  [FAIL] 必須CLIが見つかりません: $name"
      $failCount++
    }
  }
  if ($failCount -gt 0) {
    Write-Err "doctor: FAILが $failCount 件あります"
    exit 1
  }
  Write-Info "doctor: FAILなし"
  exit 0
}

Write-Info "--- prereq検査 ---"
$missing = $false
foreach ($name in $Manifest.prereqs.required) {
  if (Get-Command $name -ErrorAction SilentlyContinue) {
    Write-Info "  必須CLI検出: $name"
  } else {
    $hint = $Manifest.prereqs.installHints.windows.$name
    Write-Err "  必須CLIが見つかりません: $name ($hint)"
    $missing = $true
  }
}
if ($missing) {
  Write-Err "必須CLIが不足しているため中断します"
  exit 1
}

Write-Info "--- ~/.claude へのcopyインストール ---"
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null
foreach ($entry in $Manifest.linkEntries) {
  $livePath = Join-Path $ClaudeDir $entry.claudePath
  $repoPath = Join-Path $RepoRoot $entry.repoPath
  if (Test-Path $livePath) {
    Write-Warn "$($entry.name) は既に存在するためskipします（上書きしません。再インストールしたい場合は手動で削除してください）"
    continue
  }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $livePath) | Out-Null
  Copy-Item -Recurse -Path $repoPath -Destination $livePath
  Write-Info "copyしました: $($entry.name)"
}

Write-Info "インストール完了（Windows/copy運用。'install.ps1 -Check' で状態を確認できます）"
