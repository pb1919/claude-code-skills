#!/usr/bin/env python3
"""
Build script: packages claude-code-skills into distributable zip archives.

Produces two types of output:
  1. Full distribution zip  (Claude Code CLI / symlink install)
  2. Individual skill zips  (Claude Desktop upload - one zip per skill)

Uses `git archive` / `git ls-files` so only committed, tracked files are
included. Commit your changes before building to include them.

Usage:
    python3 build.py                    # Build everything (default)
    python3 build.py --version v1.2.0   # Override version string
    python3 build.py --list             # Preview files that would be included
    python3 build.py --output DIR       # Write archives to a custom directory

Output:
    dist/claude-code-skills-{version}.zip   # Full distribution (Claude Code)
    dist/skills/agile-board.zip             # Individual skill (Claude Desktop)
    dist/skills/developer-analysis.zip
    dist/skills/git-workflow.zip
    dist/skills/project-management.zip
    dist/skills/requirements-design.zip
    dist/skills/testing.zip
"""

import argparse
import subprocess
import sys
import zipfile
from datetime import datetime
from pathlib import Path


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def get_version(repo_dir: Path) -> str:
    """Derive version from git tags, falling back to YYYYMMDD date."""
    try:
        result = subprocess.run(
            ["git", "describe", "--tags", "--always", "--dirty"],
            capture_output=True,
            text=True,
            cwd=repo_dir,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except FileNotFoundError:
        print("Warning: git not found, using date-based version", file=sys.stderr)
    return datetime.now().strftime("%Y%m%d")


def get_uncommitted_changes(repo_dir: Path) -> list[str]:
    """Return tracked files with uncommitted changes (excludes untracked files)."""
    result = subprocess.run(
        ["git", "status", "--porcelain"],
        capture_output=True,
        text=True,
        cwd=repo_dir,
    )
    # '??' prefix = untracked; skip those since git archive never includes them
    return [line for line in result.stdout.splitlines() if line.strip() and not line.startswith("??")]


def ls_files(repo_dir: Path, path: str = "") -> list[str]:
    """Return git-tracked files, optionally filtered to a sub-path."""
    cmd = ["git", "ls-files"]
    if path:
        cmd.append(path)
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=repo_dir)
    if result.returncode != 0:
        print("Error: git ls-files failed", file=sys.stderr)
        sys.exit(1)
    return sorted(f for f in result.stdout.splitlines() if f.strip())


def format_size(path: Path) -> str:
    kb = path.stat().st_size // 1024
    return f"{kb} KB" if kb < 1024 else f"{kb / 1024:.1f} MB"


# ---------------------------------------------------------------------------
# Build: full distribution zip  (Claude Code CLI)
# ---------------------------------------------------------------------------

def build_full(repo_dir: Path, version: str, output_dir: Path) -> Path:
    """Create the full distribution zip using git archive."""
    output_dir.mkdir(parents=True, exist_ok=True)
    archive_path = output_dir / f"claude-code-skills-{version}.zip"

    result = subprocess.run(
        ["git", "archive", "--format=zip", f"--output={archive_path}", "HEAD"],
        cwd=repo_dir,
    )
    if result.returncode != 0:
        print("Error: git archive failed", file=sys.stderr)
        sys.exit(1)

    return archive_path


# ---------------------------------------------------------------------------
# Build: individual skill zips  (Claude Desktop)
# ---------------------------------------------------------------------------

def build_skill(repo_dir: Path, skill_name: str, output_dir: Path) -> Path:
    """
    Create a single skill zip suitable for Claude Desktop upload.

    Claude Desktop requires the skill folder to be the root of the zip:
        agile-board.zip
        └── agile-board/
            ├── SKILL.md
            ├── references/
            └── scripts/
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    archive_path = output_dir / f"{skill_name}.zip"

    skill_src_prefix = f"skills/{skill_name}/"
    tracked = ls_files(repo_dir, skill_src_prefix)

    if not tracked:
        print(f"  Warning: no tracked files found for skill '{skill_name}', skipping")
        return archive_path

    with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for git_path in tracked:
            # Rewrite path inside zip:
            #   skills/agile-board/SKILL.md  →  agile-board/SKILL.md
            rel = git_path[len(skill_src_prefix):]
            arcname = f"{skill_name}/{rel}"
            zf.write(repo_dir / git_path, arcname)

    return archive_path


def discover_skills(repo_dir: Path) -> list[str]:
    """Return skill names by finding skills/*/SKILL.md in tracked files."""
    tracked = ls_files(repo_dir, "skills/")
    names: list[str] = []
    for f in tracked:
        parts = Path(f).parts  # ('skills', 'agile-board', 'SKILL.md')
        if len(parts) >= 3 and parts[2] == "SKILL.md":
            names.append(parts[1])
    return sorted(set(names))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build distributable zip archives of claude-code-skills",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--version", help="Override version string (e.g. v1.2.0)")
    parser.add_argument(
        "--output",
        default="dist",
        metavar="DIR",
        help="Root output directory (default: dist/)",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="Preview tracked files that would be packaged, then exit",
    )
    args = parser.parse_args()

    repo_dir = Path(__file__).parent.resolve()
    version = args.version or get_version(repo_dir)
    output_dir = (
        Path(args.output) if Path(args.output).is_absolute()
        else repo_dir / args.output
    )

    # --list: preview and exit
    if args.list:
        all_files = ls_files(repo_dir)
        print(f"Full distribution ({len(all_files)} files):")
        for f in all_files:
            print(f"  {f}")
        print()
        skills = discover_skills(repo_dir)
        print(f"Individual skills to package for Claude Desktop ({len(skills)}):")
        for s in skills:
            files = ls_files(repo_dir, f"skills/{s}/")
            print(f"  {s}  ({len(files)} files)")
        return

    # Warn about uncommitted changes
    changes = get_uncommitted_changes(repo_dir)
    if changes:
        print("Warning: uncommitted changes will NOT be included in the archives.")
        print("Run 'git commit' first to include them:\n")
        for change in changes[:20]:
            print(f"  {change}")
        if len(changes) > 20:
            print(f"  ... and {len(changes) - 20} more")
        print()

    built: list[Path] = []

    # 1. Full distribution zip (Claude Code)
    full_zip = build_full(repo_dir, version, output_dir)
    print(f"Full distribution:  {full_zip.relative_to(repo_dir)}  ({format_size(full_zip)})")
    built.append(full_zip)

    # 2. Individual skill zips (Claude Desktop)
    skills_dir = output_dir / "skills"
    skills = discover_skills(repo_dir)
    print(f"\nClaude Desktop skills ({len(skills)}):")
    for skill_name in skills:
        skill_zip = build_skill(repo_dir, skill_name, skills_dir)
        print(f"  {skill_zip.relative_to(repo_dir)}  ({format_size(skill_zip)})")
        built.append(skill_zip)

    print()
    print("--- Install instructions ---")
    print()
    print("Claude Code (Linux/Mac):")
    print(f"  unzip {full_zip.name} -d claude-code-skills && cd claude-code-skills && bash install.sh")
    print()
    print("Claude Code (Windows):")
    print(f"  Expand-Archive {full_zip.name} -DestinationPath claude-code-skills")
    print("  cd claude-code-skills && .\\install.ps1")
    print()
    print("Claude Desktop:")
    print("  Settings > Capabilities > Skills > Upload ZIP")
    print(f"  Upload individual skill zips from: {skills_dir.relative_to(repo_dir)}/")


if __name__ == "__main__":
    main()
