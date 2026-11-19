<#
.SYNOPSIS
    把「万法阁」源码初始化并推送到 GitHub 仓库。

.DESCRIPTION
    本脚本只做本地 git 操作 + push，不碰游戏目录、不改 mod 内容。
    首次运行会 git init、建 main 分支、加 origin、提交全部源码并推送；
    之后再运行就只做「提交 + 推送」。

.NOTES
    仓库：https://github.com/Lenonss/LBQDXXMNQ_MOD_WangFaGe
    认证：HTTPS 推送时密码位置填 GitHub Personal Access Token（repo 权限），
          不要填账号密码。想免输入用 SSH remote。
#>

$ErrorActionPreference = 'Stop'

$RepoUrl = 'https://github.com/Lenonss/LBQDXXMNQ_MOD_WangFaGe.git'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root
Write-Host "仓库根目录：$Root" -ForegroundColor Cyan

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw '没找到 git，请先安装 Git for Windows。'
}

if (-not (Test-Path (Join-Path $Root '.git'))) {
    Write-Host '未检测到 .git，初始化仓库…' -ForegroundColor Yellow
    git init | Out-Null
    git branch -M main
} else {
    Write-Host '.git 已存在，跳过初始化。' -ForegroundColor DarkGray
}

$remotes = git remote
if ($remotes -notcontains 'origin') {
    git remote add origin $RepoUrl
    Write-Host "已添加 origin -> $RepoUrl" -ForegroundColor Yellow
} else {
    $current = git remote get-url origin
    if ($current -ne $RepoUrl) {
        Write-Host "origin 当前是 $current，改为 $RepoUrl" -ForegroundColor Yellow
        git remote set-url origin $RepoUrl
    }
}

git add -A
$pending = git status --porcelain
if ([string]::IsNullOrWhiteSpace($pending)) {
    Write-Host '没有需要提交的改动。' -ForegroundColor DarkGray
} else {
    $msg = Read-Host '提交说明（直接回车用默认值）'
    if ([string]::IsNullOrWhiteSpace($msg)) {
        $msg = 'chore: 同步源码'
    }
    git commit -m $msg | Out-Null
    Write-Host "已提交：$msg" -ForegroundColor Green
}

git push -u origin main
if ($LASTEXITCODE -ne 0) {
    throw '推送失败：检查是否已登录（HTTPS 用 Personal Access Token 当密码），或用 SSH remote。'
}

Write-Host ''
Write-Host '推送完成。发版流程：' -ForegroundColor Cyan
Write-Host '  1. python tools/bump_version.py 2.1.0'
Write-Host '  2. 在 CHANGELOG.md 顶部补 ## v2.1.0'
Write-Host '  3. git add -A; git commit -m "release: v2.1.0"'
Write-Host '  4. git tag v2.1.0; git push origin main --tags'
Write-Host '  → GitHub Actions 自动打包并发布 Release（zip 供 PC 与安卓下载）'
