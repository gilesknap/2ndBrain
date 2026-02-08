"""Interface for ``python -m brain``."""

from argparse import ArgumentParser
from collections.abc import Sequence
from pathlib import Path

from . import __version__
from .app import main as run_app

__all__ = ["main"]


def main(args: Sequence[str] | None = None) -> None:
    """Entry point — parse CLI args then dispatch to the chosen command."""
    parser = ArgumentParser(
        description="2ndBrain: Gemini-powered Slack→Obsidian capture system"
    )
    parser.add_argument(
        "-v",
        "--version",
        action="version",
        version=__version__,
    )

    sub = parser.add_subparsers(dest="command")

    # --- run (default: start the Slack listener) ---
    sub.add_parser("run", help="Start the Slack socket-mode listener")

    # --- migrate: vault maintenance operations ---
    mig = sub.add_parser("migrate", help="Update vault notes to current standards")
    mig.add_argument(
        "--vault",
        type=Path,
        default=None,
        help="Vault root path (default: ~/Documents/2ndBrain/2ndBrainVault)",
    )
    mig.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without modifying files",
    )
    mig.add_argument(
        "--rename",
        action="store_true",
        help="Rename hyphenated-slug files to Title Case",
    )
    mig.add_argument(
        "--fix-frontmatter",
        action="store_true",
        help="Sync category field with folder, add missing properties",
    )
    mig.add_argument(
        "--update-links",
        action="store_true",
        help="Update wiki-links to match renamed files",
    )
    mig.add_argument(
        "--reclassify",
        action="store_true",
        help="Use Gemini AI to re-evaluate categories and tags",
    )
    mig.add_argument(
        "--all",
        action="store_true",
        help="Run all non-AI migrations (rename, fix-fm, links)",
    )

    parsed = parser.parse_args(args)

    if parsed.command == "migrate":
        _run_migrate(parsed)
    else:
        # Default: start the Slack listener (both "run" and no subcommand)
        run_app()


def _run_migrate(parsed) -> None:
    """Execute the migrate subcommand."""
    import logging

    from dotenv import load_dotenv

    from .migrate import run_migration

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(levelname)s - %(message)s",
    )

    load_dotenv()

    vault_path = parsed.vault or (
        Path.home() / "Documents" / "2ndBrain" / "2ndBrainVault"
    )

    if not vault_path.exists():
        logging.critical("Vault not found at %s", vault_path)
        raise SystemExit(1)

    do_all = parsed.all
    run_migration(
        vault_path,
        rename=do_all or parsed.rename,
        fix_fm=do_all or parsed.fix_frontmatter,
        update_links=do_all or parsed.update_links,
        reclassify=parsed.reclassify,
        dry_run=parsed.dry_run,
    )


if __name__ == "__main__":
    main()
