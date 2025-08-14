<#
.概要
  sing-box 管理脚本（兼容 PowerShell 5.1）
.说明
  功能：
    1) 安装 sing-box（通过 scoop；若检测到已安装 scoop 则跳过 bootstrap/init）
    2) 更新/下载 config.json（支持修改默认地址并写回本脚本）
    3) 卸载 sing-box（使用 scoop uninstall sing-box）
    4) 更新或卸载本脚本（支持从默认地址更新脚本）
#>

# 可被脚本回写的默认变量
$DefaultConfigUrl = 'https://example.com/config.json'
$DefaultScriptUrl = 'https://raw.githubusercontent.com/Leovikii/sm/main/shell/sm.ps1'

# 兼容模式（避免较新严格模式带来的问题）
Set-StrictMode -Off

# 简易输出函数
function Write-Info { param($s) Write-Host "[*] $s" -ForegroundColor Cyan }
function Write-OK   { param($s) Write-Host "[+] $s" -ForegroundColor Green }
function Write-Err  { param($s) Write-Host "[-] $s" -ForegroundColor Red }

# 脚本路径与常用路径
$ScriptPath = $MyInvocation.MyCommand.Definition
$UserProfile = $env:USERPROFILE
$ScoopAppsSingBoxPath = Join-Path $UserProfile "scoop\apps\sing-box"
$StartMenuPrograms = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$SingBoxStartMenuFolder = Join-Path $StartMenuPrograms "sing-box"

# 获取已安装的 sing-box 目录（返回最新版本）
function Get-InstalledSingBoxFolder {
    if (-not (Test-Path $ScoopAppsSingBoxPath)) { return $null }
    try {
        $dirs = Get-ChildItem -Path $ScoopAppsSingBoxPath -Directory -ErrorAction Stop | Sort-Object Name -Descending
        if ($dirs -and $dirs.Count -gt 0) { return $dirs[0].FullName } else { return $null }
    } catch {
        return $null
    }
}

# 生成 start/stop 批处理与开始菜单快捷方式（保持批处理无中文）
function Create-StartStopBatAndShortcuts {
    param([string]$InstallFolder)
    if (-not (Test-Path $InstallFolder)) {
        Write-Err "Install folder not found: $InstallFolder"
        return $false
    }

    # 绝对路径
    $singExePath = Join-Path $InstallFolder 'sing-box.exe'
    $configPath  = Join-Path $InstallFolder 'config.json'

    # 构造 powershell Start-Process 命令并 base64 编码以避免嵌套引号问题
    $psCommand = "Start-Process -FilePath '$singExePath' -ArgumentList 'run -c `"$configPath`"' -Verb RunAs -WorkingDirectory '$InstallFolder' -WindowStyle Minimized"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($psCommand))

    # start/stop 批处理内容（无中文注释）
    $startContent = @"
@echo off
set "SING_EXE=$singExePath"
set "CONFIG_PATH=$configPath"
powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded
exit /b
"@

    $stopContent = @"
@echo off
tasklist /FI "IMAGENAME eq sing-box.exe" 2>NUL | find /I "sing-box.exe" >NUL
if %ERRORLEVEL%==0 (
    taskkill /IM sing-box.exe /F
    echo sing-box stopped
) else (
    echo sing-box not running
)
exit /b
"@

    try {
        $startBat = Join-Path $InstallFolder 'start-sing-box.bat'
        $stopBat  = Join-Path $InstallFolder 'stop-sing-box.bat'

        # 写入批处理文件（使用 ASCII 编码以兼容各种环境）
        $startContent | Out-File -FilePath $startBat -Encoding ASCII -Force
        $stopContent  | Out-File -FilePath $stopBat  -Encoding ASCII -Force

        Write-OK "Created: $startBat"
        Write-OK "Created: $stopBat"

        # 在开始菜单创建快捷方式
        if (-not (Test-Path $SingBoxStartMenuFolder)) {
            New-Item -ItemType Directory -Path $SingBoxStartMenuFolder -Force | Out-Null
            Write-OK "Created start menu folder: $SingBoxStartMenuFolder"
        }

        $wsh = New-Object -ComObject WScript.Shell

        $lnkStart = Join-Path $SingBoxStartMenuFolder "Start sing-box.lnk"
        $shortcut = $wsh.CreateShortcut($lnkStart)
        $shortcut.TargetPath = $startBat
        $shortcut.WorkingDirectory = $InstallFolder
        $shortcut.WindowStyle = 7
        $shortcut.IconLocation = $singExePath
        $shortcut.Save()
        Write-OK "Created start shortcut: Start sing-box"

        $lnkStop = Join-Path $SingBoxStartMenuFolder "Stop sing-box.lnk"
        $shortcut2 = $wsh.CreateShortcut($lnkStop)
        $shortcut2.TargetPath = $stopBat
        $shortcut2.WorkingDirectory = $InstallFolder
        $shortcut2.WindowStyle = 1
        $shortcut2.IconLocation = $singExePath
        $shortcut2.Save()
        Write-OK "Created stop shortcut: Stop sing-box"

        return $true
    } catch {
        Write-Err "Failed to create batch or shortcuts: $($_.Exception.Message)"
        return $false
    }
}

# 安装 sing-box（若检测到 scoop 则跳过 bootstrap/init）
function Install-SingBox {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "          安装 sing-box" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    try {
        $scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue

        if ($scoopCmd) {
            Write-Info "检测到 scoop，跳过 bootstrap/init。开始安装 sing-box (spc/sing-box)..."
            & scoop install spc/sing-box
        } else {
            Write-Info "未检测到 scoop，开始 bootstrap 并安装依赖..."
            Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
            Write-OK "已将 ExecutionPolicy 设为 RemoteSigned (CurrentUser)"

            Write-Info "正在 bootstrap scoop..."
            Invoke-Expression (Invoke-WebRequest -UseBasicParsing -Uri 'http://scoop.201704.xyz' -ErrorAction Stop).Content
            Write-OK "scoop bootstrap 完成"

            Write-Info "安装 git..."
            & scoop install git

            Write-Info "添加 spc 桶..."
            & scoop bucket add spc https://gitee.com/wlzwme/scoop-proxy-cn.git

            Write-Info "更新 scoop..."
            & scoop update

            Write-Info "安装 sing-box..."
            & scoop install spc/sing-box
        }

        Start-Sleep -Seconds 1
        $installDir = Get-InstalledSingBoxFolder
        if ($installDir) {
            Write-OK "sing-box 安装目录： $installDir"
            if (Create-StartStopBatAndShortcuts -InstallFolder $installDir) {
                Write-OK "初始化完成。开始菜单 -> sing-box 中已创建快捷方式。"
            } else {
                Write-Err "初始化（创建批处理/快捷方式）失败，请检查权限。"
            }
        } else {
            Write-Err "未能找到 sing-box 安装目录，请检查 scoop 输出。"
        }
    } catch {
        Write-Err "安装出错：$($_.Exception.Message)"
    }

    Write-Host ""
    Read-Host "按回车返回主菜单..."
}

# 下载并放置 config.json（下载后重命名并移动到安装目录）
function Download-And-PlaceConfig {
    param([string]$UrlToDownload)

    if (-not $UrlToDownload) { Write-Err "未指定 URL"; return $false }
    $installDir = Get-InstalledSingBoxFolder
    if (-not $installDir) { Write-Err "未检测到 sing-box 安装，请先安装。"; return $false }

    Write-Info "从以下地址下载配置： $UrlToDownload"
    $tmpFile = Join-Path $env:TEMP ("singbox_config_tmp_{0}.json" -f ([guid]::NewGuid().ToString()))
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $UrlToDownload -OutFile $tmpFile -ErrorAction Stop
        Write-OK "下载完成： $tmpFile"

        $dest = Join-Path $installDir 'config.json'
        if (Test-Path $dest) {
            $bak = $dest + "." + (Get-Date -Format "yyyyMMddHHmmss") + ".bak"
            Copy-Item -Path $dest -Destination $bak -Force
            Write-Info "已备份现有 config 到： $bak"
        }
        Move-Item -Path $tmpFile -Destination $dest -Force
        Write-OK "已将配置移动到： $dest"
        return $true
    } catch {
        Write-Err "下载或移动失败：$($_.Exception.Message)"
        if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
        return $false
    }
}

# 二级菜单：更新 config（支持写回脚本）
function Update-ConfigMenu {
    while ($true) {
        Clear-Host
        Write-Host "———— 配置更新 ————" -ForegroundColor Cyan
        Write-Host "1) 修改默认下载地址（并写回脚本）"
        Write-Host "2) 使用自定义地址下载并替换为 config.json"
        Write-Host "3) 使用当前默认地址下载并替换为 config.json"
        Write-Host "0) 返回主菜单"
        Write-Host ""
        Write-Host "当前默认地址： $DefaultConfigUrl"
        Write-Host ""
        $choice = Read-Host "请选择 (0/1/2/3)"
        switch ($choice) {
            '1' {
                $new = Read-Host "请输入新的默认 config 下载地址"
                if (-not $new) { Write-Err "地址为空，已取消。"; Start-Sleep -Seconds 1; continue }

                $tmp = $null
                try {
                    # 读取脚本内容（UTF8）
                    $scriptText = Get-Content -Path $ScriptPath -Raw -Encoding UTF8 -ErrorAction Stop

                    # 在单引号字符串中把单引号替换为两个单引号以做转义
                    $escapedForSingle = $new -replace "'", "''"

                    # 正则：匹配 $DefaultConfigUrl = '...' 或 "..."
                    $pattern = '(?m)^\s*\$DefaultConfigUrl\s*=\s*([''"]).*?\1\s*$'

                    if ([regex]::IsMatch($scriptText, $pattern)) {
                        $replacement = '$DefaultConfigUrl = ' + "'" + $escapedForSingle + "'"
                        $newScript = [regex]::Replace($scriptText, $pattern, $replacement)
                    } else {
                        # 若未找到则在文件开头插入声明
                        $insertion = '$DefaultConfigUrl = ' + "'" + $escapedForSingle + "'" + "`r`n"
                        $newScript = $insertion + $scriptText
                    }

                    # 先写临时文件再替换原文件（原子替换）
                    $tmp = $ScriptPath + ".tmp"
                    Set-Content -Path $tmp -Value $newScript -Encoding UTF8 -Force
                    Move-Item -Path $tmp -Destination $ScriptPath -Force

                    Write-OK "已将默认配置地址写回脚本： $ScriptPath"

                    # 立即更新当前会话中的变量
                    Set-Variable -Name DefaultConfigUrl -Value $new -Scope Global -Force
                    Write-OK "当前会话中的 DefaultConfigUrl 已更新为： $new"
                } catch {
                    Write-Err "写回失败：$($_.Exception.Message)"
                    try { if ($tmp -and (Test-Path $tmp)) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } } catch {}
                }

                Start-Sleep -Seconds 1
            }
            '2' {
                $url = Read-Host "请输入自定义下载地址"
                if (-not $url) { Write-Err "地址为空，已取消。"; Start-Sleep -Seconds 1; continue }
                if (Download-And-PlaceConfig -UrlToDownload $url) { Write-OK "自定义地址下载并安装成功。" }
                Start-Sleep -Seconds 1
            }
            '3' {
                if (-not $DefaultConfigUrl) { Write-Err "默认地址为空，请先设置。"; Start-Sleep -Seconds 1; continue }
                if (Download-And-PlaceConfig -UrlToDownload $DefaultConfigUrl) { Write-OK "默认地址下载并安装成功。" }
                Start-Sleep -Seconds 1
            }
            '0' {
                # 返回到主菜单
                return
            }
            default {
                Write-Err "无效选项"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# 卸载 sing-box（调用 scoop uninstall）
function Uninstall-SingBox {
    Clear-Host
    Write-Host "———— 卸载 sing-box ————" -ForegroundColor Cyan
    $installDir = Get-InstalledSingBoxFolder
    if (-not $installDir) { Write-Err "未检测到 sing-box，跳过卸载。"; Start-Sleep -Seconds 1; return }
    Write-Host "检测到安装目录： $installDir"
    $confirm = Read-Host "确认执行 'scoop uninstall sing-box' 吗？(y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') { Write-Info "已取消"; Start-Sleep -Seconds 1; return }

    try {
        & scoop uninstall sing-box
        Write-OK "已执行 scoop uninstall sing-box"
        if (Test-Path $installDir) {
            Remove-Item -Path $installDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Info "尝试删除残留目录： $installDir"
        }
        if (Test-Path $SingBoxStartMenuFolder) {
            Remove-Item -Path $SingBoxStartMenuFolder -Recurse -Force -ErrorAction SilentlyContinue
            Write-Info "已删除开始菜单文件夹： $SingBoxStartMenuFolder"
        }
        Write-OK "卸载完成（如需查看详细信息请检查 scoop 输出）"
    } catch {
        Write-Err "卸载出错： $($_.Exception.Message)"
    }

    Start-Sleep -Seconds 1
}

# 二级菜单：更新或卸载脚本（修复返回主菜单）
function UpdateOrUninstall-ScriptMenu {
    while ($true) {
        Clear-Host
        Write-Host "———— 更新 / 卸载 脚本 ————" -ForegroundColor Cyan
        Write-Host "1) 更新脚本（从默认地址下载并覆盖当前脚本）"
        Write-Host "2) 删除本脚本并清理（可选择同时卸载 sing-box）"
        Write-Host "0) 返回主菜单"
        Write-Host ""
        Write-Host "默认更新地址： $DefaultScriptUrl"
        Write-Host ""
        $c = Read-Host "请选择 (0/1/2)"
        switch ($c) {
            '1' {
                if (-not $DefaultScriptUrl) { Write-Err "默认更新地址为空"; Start-Sleep -Seconds 1; continue }
                try {
                    $tmp = Join-Path $env:TEMP ("sm_update_{0}.ps1" -f ([guid]::NewGuid().ToString()))
                    Invoke-WebRequest -UseBasicParsing -Uri $DefaultScriptUrl -OutFile $tmp -ErrorAction Stop
                    $newContent = Get-Content -Path $tmp -Raw -ErrorAction Stop -Encoding UTF8
                    Set-Content -Path $ScriptPath -Value $newContent -Force -Encoding UTF8
                    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
                    Write-OK "脚本已更新： $ScriptPath"
                    Write-Info "注意：当前会话仍使用旧内容，重启后使用新脚本。"
                } catch {
                    Write-Err "更新失败： $($_.Exception.Message)"
                }
                Start-Sleep -Seconds 1
            }
            '2' {
                $confirm = Read-Host "确认删除当前脚本 $ScriptPath 吗？(y/N)"
                if ($confirm -ne 'y' -and $confirm -ne 'Y') { Write-Info "已取消"; Start-Sleep -Seconds 1; continue }
                $u = Read-Host "是否同时卸载 sing-box？(y/N)"
                if ($u -eq 'y' -or $u -eq 'Y') { Uninstall-SingBox }
                try {
                    if (Test-Path $SingBoxStartMenuFolder) {
                        Remove-Item -Path $SingBoxStartMenuFolder -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Info "已删除开始菜单文件夹： $SingBoxStartMenuFolder"
                    }
                    Remove-Item -Path $ScriptPath -Force -ErrorAction SilentlyContinue
                    Write-OK "脚本已删除： $ScriptPath"
                    Write-OK "清理完成。"
                    exit 0
                } catch {
                    Write-Err "删除或清理出错： $($_.Exception.Message)"
                    Start-Sleep -Seconds 1
                }
            }
            '0' {
                # 返回主菜单
                return
            }
            default {
                Write-Err "无效选项"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# 主菜单（循环）
function MainMenu {
    while ($true) {
        Clear-Host
        Write-Host "===============================================" -ForegroundColor Cyan
        Write-Host "           sing-box Manager for Windows" -ForegroundColor Cyan
        Write-Host "===============================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host " 1) 安装 sing-box"
        Write-Host "    说明：使用scoop安装"
        Write-Host ""
        Write-Host " 2) 更新 / 下载 config.json"
        Write-Host "    说明：可修改默认下载地址并写回脚本，或使用自定义地址下载并替换 config.json"
        Write-Host ""
        Write-Host " 3) 卸载 sing-box"
        Write-Host ""
        Write-Host " 4) 更新或卸载本脚本"
        Write-Host "    说明：支持从默认地址更新脚本或删除脚本并清理产生的文件"
        Write-Host ""
        Write-Host " 0) 退出"
        Write-Host ""
        $sel = Read-Host "请选择 (0/1/2/3/4)"
        switch ($sel) {
            '1' { Install-SingBox }
            '2' { Update-ConfigMenu }
            '3' { Uninstall-SingBox }
            '4' { UpdateOrUninstall-ScriptMenu }
            '0' { Write-Info "退出。"; return }
            default {
                Write-Err "无效选项，请重试。"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# 启动时简单检测
$installed = Get-InstalledSingBoxFolder
if ($installed) { Write-OK "检测到 sing-box 安装目录： $installed" } else { Write-Info "未检测到 sing-box。可通过菜单安装。" }

# 运行主菜单
MainMenu
