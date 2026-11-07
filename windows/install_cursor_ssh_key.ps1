# 在 4070 那台 Windows 上运行，把本机的 SSH 公钥写入 OpenSSH。
# 右键“以管理员身份运行”PowerShell 后执行:
#   powershell -ExecutionPolicy Bypass -File .\install_cursor_ssh_key.ps1
# 只需要这一个文件，不必拷贝整个仓库。

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$PubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINHUoQzalI2XI0aEtGM8KFO2DgUu1xY0CY1MgTM52V76 cursor-win4070"
$KeyMarker = "AAAAC3NzaC1lZDI1NTE5AAAAINHUoQzalI2XI0aEtGM8KFO2DgUu1xY0CY1MgTM52V76"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Add-PublicKey([string]$FilePath) {
    $directory = Split-Path -Parent $FilePath
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    if (Test-Path $FilePath) {
        $existing = Get-Content -Path $FilePath -Raw -ErrorAction SilentlyContinue
        if ($existing -and $existing.Contains($KeyMarker)) {
            Write-Host "公钥已存在: $FilePath"
            return
        }
        Add-Content -Path $FilePath -Value $PubKey -Encoding ascii
    } else {
        Set-Content -Path $FilePath -Value $PubKey -Encoding ascii
    }
    Write-Host "已写入: $FilePath"
}

function Protect-AdminKey([string]$FilePath) {
    & icacls.exe $FilePath /inheritance:r | Out-Null
    & icacls.exe $FilePath /grant "*S-1-5-18:F" | Out-Null
    & icacls.exe $FilePath /grant "*S-1-5-32-544:F" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "设置管理员密钥权限失败: $FilePath"
    }
    Write-Host "已收紧权限: $FilePath"
}

$isAdmin = Test-IsAdmin
Write-Host "当前用户: $env:USERNAME"
Write-Host "管理员权限: $isAdmin"

if ($isAdmin) {
    $capability = Get-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0"
    if ($capability.State -ne "Installed") {
        Write-Host "正在安装 OpenSSH 服务器..."
        Add-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" | Out-Null
    }
    Start-Service sshd
    Set-Service -Name sshd -StartupType Automatic
    $firewall = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    if (-not $firewall) {
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    }
    Write-Host "sshd 已启动，并设置为开机自启。"
} else {
    Write-Host "当前不是管理员。将只写入当前用户的 authorized_keys。"
    Write-Host "若要用管理员账户登录，请改用管理员 PowerShell 重新运行本脚本。"
}

$userKey = Join-Path $env:USERPROFILE ".ssh\authorized_keys"
Add-PublicKey $userKey

if ($isAdmin) {
    $adminKey = "C:\ProgramData\ssh\administrators_authorized_keys"
    Add-PublicKey $adminKey
    Protect-AdminKey $adminKey
}

Write-Host ""
Write-Host "完成。请把下面两行发回连接方，填进 ~/.ssh/config 的 Host win4070："
Write-Host "HostName $(hostname)"
Write-Host "User $env:USERNAME"
