# Claude Code Skills & Commands Installer (Windows)
#
# Usage:
#   .\install.ps1                           # Global install (symlinks to $HOME\.claude\)  — needs admin OR Developer Mode
#   .\install.ps1 -Project                  # Per-project install (copies to .\.claude\, gitignored by default)
#   .\install.ps1 -Project C:\path\to\repo  # Per-project install into a specific dir
#   .\install.ps1 -Project -NoGitignore     # Per-project install WITHOUT gitignoring (commit & share with team)
#   .\install.ps1 -Project -Symlink         # Per-project install using symlinks (solo dev; not for git-sharing)
#
# Per-project install copies files into the project's `.claude\` folder and
# automatically adds `.claude\skills\` and `.claude\commands\` to `.gitignore`
# so they don't end up in the project's git history. Pass -NoGitignore to
# keep them out of .gitignore (e.g., to commit them and share with a team).

[CmdletBinding()]
param(
    [switch]$Project,
    [switch]$Global,
    [switch]$Symlink,
    [switch]$Gitignore,       # Back-compat alias — was required, now the default
    [switch]$NoGitignore,
    [Parameter(Position = 0)][string]$TargetDir
)

$ErrorActionPreference = "Stop"
$REPO_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Resolve mode ---
$mode = if ($Project) { "project" } elseif ($Global) { "global" } else { "global" }

if ($mode -eq "project") {
    if (-not $TargetDir) { $TargetDir = (Get-Location).Path }
    $TargetDir = (Resolve-Path $TargetDir).Path
    $SKILLS_DIR = Join-Path $TargetDir ".claude\skills"
    $COMMANDS_DIR = Join-Path $TargetDir ".claude\commands"
    $locationLabel = "project ($TargetDir)"
    $useSymlink = [bool]$Symlink
} else {
    $SKILLS_DIR = Join-Path $env:USERPROFILE ".claude\skills"
    $COMMANDS_DIR = Join-Path $env:USERPROFILE ".claude\commands"
    $locationLabel = "global ($env:USERPROFILE\.claude)"
    $useSymlink = $true   # Global install always uses symlinks (for git pull updates)
}

Write-Host "Claude Code Skills and Commands Installer" -ForegroundColor Cyan
Write-Host "   From:    $REPO_DIR" -ForegroundColor Gray
Write-Host "   To:      $locationLabel" -ForegroundColor Gray
Write-Host "   Method:  $(if ($useSymlink) { 'symlink' } else { 'copy' })" -ForegroundColor Gray
Write-Host ""

if ($mode -eq "project" -and $TargetDir -eq $REPO_DIR) {
    Write-Host "Refusing to install into the skills repo itself." -ForegroundColor Yellow
    Write-Host "   Run this from inside your project, or pass the project path:"
    Write-Host "     .\install.ps1 -Project C:\path\to\your\project"
    exit 1
}

if (-not (Test-Path $SKILLS_DIR))   { New-Item -ItemType Directory -Path $SKILLS_DIR   -Force | Out-Null }
if (-not (Test-Path $COMMANDS_DIR)) { New-Item -ItemType Directory -Path $COMMANDS_DIR -Force | Out-Null }

function Install-Item {
    param(
        [string]$Source,
        [string]$Target,
        [bool]$AsSymlink
    )

    if (Test-Path $Target) {
        $existing = Get-Item $Target -Force
        if ($existing.LinkType -eq "SymbolicLink") {
            Remove-Item $Target -Force
        } elseif ($AsSymlink) {
            Write-Host "   [SKIP] Exists and is not a symlink: $Target" -ForegroundColor Yellow
            return $false
        } else {
            Remove-Item $Target -Recurse -Force
        }
    }

    try {
        if ($AsSymlink) {
            New-Item -ItemType SymbolicLink -Path $Target -Target $Source -ErrorAction Stop | Out-Null
        } else {
            Copy-Item -Path $Source -Destination $Target -Recurse -Force -ErrorAction Stop
        }
        return $true
    } catch {
        Write-Host "   [ERROR] $Target : $_" -ForegroundColor Red
        if ($AsSymlink) {
            Write-Host "           Symlinks require Administrator or Windows Developer Mode." -ForegroundColor Yellow
            Write-Host "           Try: .\install.ps1 -Project   (copies instead — no admin needed)" -ForegroundColor Yellow
        }
        return $false
    }
}

# --- Install skills ---
$installedSkills = 0
$skillsPath = Join-Path $REPO_DIR "skills"
if (Test-Path $skillsPath) {
    $skillDirs = Get-ChildItem -Path $skillsPath -Directory | Where-Object {
        (Test-Path (Join-Path $_.FullName "SKILL.md")) -and ($_.Name -notmatch "^\.")
    }

    if ($skillDirs.Count -eq 0) {
        Write-Host "Warning: No skills found in skills/" -ForegroundColor Yellow
    } else {
        foreach ($skillDir in $skillDirs) {
            $skill = $skillDir.Name
            $source = $skillDir.FullName
            $target = Join-Path $SKILLS_DIR $skill

            if (Install-Item -Source $source -Target $target -AsSymlink:$useSymlink) {
                Write-Host "[OK] Installed skill: $skill" -ForegroundColor Green
                $installedSkills++
            }
        }
    }
}

# --- Install commands ---
$installedCommands = 0
$commandsPath = Join-Path $REPO_DIR "commands"
if (Test-Path $commandsPath) {
    $commandFiles = Get-ChildItem -Path $commandsPath -Filter "*.md"

    if ($commandFiles.Count -eq 0) {
        Write-Host "Warning: No commands found in commands/" -ForegroundColor Yellow
    } else {
        foreach ($commandFile in $commandFiles) {
            $command = $commandFile.Name
            $source = $commandFile.FullName
            $target = Join-Path $COMMANDS_DIR $command

            if (Install-Item -Source $source -Target $target -AsSymlink:$useSymlink) {
                $commandName = [System.IO.Path]::GetFileNameWithoutExtension($command)
                Write-Host "[OK] Installed command: $commandName" -ForegroundColor Green
                $installedCommands++
            }
        }
    }
}

Write-Host ""
Write-Host "Installation complete:" -ForegroundColor Cyan
Write-Host "   - $installedSkills skill(s) installed to $SKILLS_DIR"
Write-Host "   - $installedCommands command(s) installed to $COMMANDS_DIR"
Write-Host ""

if ($mode -eq "project") {
    # Gitignore is on by default; -NoGitignore opts out
    $addGitignore = -not $NoGitignore

    if ($addGitignore) {
        $gitignorePath = Join-Path $TargetDir ".gitignore"
        $marker = "# Claude Code skills and commands (installed locally)"
        $existing = if (Test-Path $gitignorePath) { Get-Content $gitignorePath -Raw } else { "" }
        if ($existing -and $existing.Contains($marker)) {
            Write-Host "[i] .gitignore already has entries for .claude\skills and .claude\commands"
        } else {
            $block = "`r`n$marker`r`n.claude/skills/`r`n.claude/commands/`r`n"
            Add-Content -Path $gitignorePath -Value $block
            Write-Host "[OK] Added .claude\skills\ and .claude\commands\ to .gitignore" -ForegroundColor Green
        }
    }

    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  - Skills and commands are available inside: $TargetDir"
    if ($addGitignore) {
        Write-Host "  - .claude\skills\ and .claude\commands\ are gitignored — not committed to this repo"
        Write-Host "  - Teammates will need to run this install themselves"
        Write-Host "  - To share with the team via git instead: re-run with -NoGitignore and commit the folders"
    } else {
        Write-Host "  - .claude\skills\ and .claude\commands\ are NOT gitignored — commit them to share with teammates:"
        Write-Host "      git add .claude\skills .claude\commands; git commit -m `"chore: add Claude Code skills and commands`""
    }
    Write-Host "  - For agile-board: python $REPO_DIR\skills\agile-board\scripts\setup.py"
    if (-not $useSymlink) {
        Write-Host "  - To update: re-run this script after 'git pull' in $REPO_DIR"
    } else {
        Write-Host "  - To update: git pull in $REPO_DIR  (symlinks track automatically)"
    }
} else {
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  - Skills and commands are now available globally for all projects"
    Write-Host "  - For agile-board: python $REPO_DIR\skills\agile-board\scripts\setup.py  (run inside each project)"
    Write-Host "  - To update: git pull in $REPO_DIR  (symlinks track automatically)"
}
