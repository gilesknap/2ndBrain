"""Tests for vault migration utilities."""

import textwrap
from pathlib import Path

import pytest

from brain.migrate import (
    _is_hyphenated_slug,
    _read_frontmatter,
    _slug_to_title,
    _title_to_filename,
    _write_frontmatter,
    fix_frontmatter,
    rename_to_title_case,
    update_wiki_links,
)

# ------------------------------------------------------------------
# Fixtures
# ------------------------------------------------------------------


@pytest.fixture()
def vault(tmp_path: Path) -> Path:
    """Create a minimal vault structure with sample notes."""
    # Create category folders
    for folder in ("Projects", "Actions", "Media", "Reference", "Inbox", "Attachments"):
        (tmp_path / folder).mkdir()

    # Also create a Demo folder (should be skipped)
    (tmp_path / "Demo").mkdir()
    (tmp_path / "_brain").mkdir()

    # --- Projects ---
    (tmp_path / "Projects" / "brain-project-setup.md").write_text(
        textwrap.dedent("""\
        ---
        title: Brain Project Copier Template Setup
        date: 2026-02-07 17:20
        source: slack
        category: Projects
        tags:
          - project-setup
          - python
        project_name: brain-project-setup
        priority: medium
        tokens_used: 3894
        ---

        ### Notes
        This project uses [[copier-template]] for scaffolding.
        """),
        encoding="utf-8",
    )

    # --- Media ---
    (tmp_path / "Media" / "faithless-englefield-estate.md").write_text(
        textwrap.dedent("""\
        ---
        title: Faithless at Englefield Estate
        date: 2026-02-07T16:08:00
        source: slack
        category: Media
        tags:
          - music
          - event
        media_title: Faithless at Englefield Estate
        media_type: article
        creator: Englefield Estate
        url: https://www.englefieldestate.co.uk/whats-on/faithless
        status: to_consume
        tokens_used: 1610
        ---

        ### Event
        Faithless performing at Englefield Estate.
        """),
        encoding="utf-8",
    )

    # --- Reference (with category mismatch) ---
    (tmp_path / "Reference" / "android-slack-share-sheet-shortcut.md").write_text(
        textwrap.dedent("""\
        ---
        title: "Android: Add Slack Channel to Share Sheet"
        date: 2026-02-07 14:15
        source: slack
        category: Inbox
        tags:
          - android
          - slack
        tokens_used: 2628
        ---

        ### How-to
        Steps to add Slack channel shortcut.
        """),
        encoding="utf-8",
    )

    # --- Demo (should be skipped) ---
    (tmp_path / "Demo" / "millie-dog.md").write_text(
        textwrap.dedent("""\
        ---
        title: Millie Dog
        date: 2026-02-07 16:31
        source: slack
        category: Inbox
        tags:
          - dog
        tokens_used: 1837
        ---

        ### Photo
        Good dog.
        """),
        encoding="utf-8",
    )

    # --- A note with a wiki-link to a project ---
    (tmp_path / "Actions" / "fix-garden-fence.md").write_text(
        textwrap.dedent("""\
        ---
        title: Fix Garden Fence
        date: 2026-02-07 10:00
        source: slack
        category: Actions
        tags:
          - garden
        action_item: Repair broken fence panel
        status: todo
        priority: high
        due_date: "2026-02-14"
        project: "[[brain-project-setup]]"
        tokens_used: 500
        ---

        ### Task
        The fence panel needs replacing. See [[faithless-englefield-estate]] for ref.
        """),
        encoding="utf-8",
    )

    return tmp_path


# ------------------------------------------------------------------
# Unit tests: helpers
# ------------------------------------------------------------------


class TestSlugToTitle:
    def test_basic(self):
        assert _slug_to_title("fix-garden-fence") == "Fix Garden Fence"

    def test_single_word(self):
        assert _slug_to_title("hello") == "Hello"

    def test_numbers(self):
        assert _slug_to_title("watch-severance-s2") == "Watch Severance S2"


class TestTitleToFilename:
    def test_basic(self):
        assert _title_to_filename("Fix Garden Fence") == "Fix Garden Fence"

    def test_strips_unsafe(self):
        assert _title_to_filename('What: "A Test"?') == "What A Test"

    def test_collapses_whitespace(self):
        assert _title_to_filename("Too   Many  Spaces") == "Too Many Spaces"


class TestIsHyphenatedSlug:
    def test_matches(self):
        assert _is_hyphenated_slug("fix-garden-fence") is True

    def test_rejects_title_case(self):
        assert _is_hyphenated_slug("Fix Garden Fence") is False

    def test_rejects_no_hyphens(self):
        assert _is_hyphenated_slug("singleword") is False

    def test_rejects_underscore_prefix(self):
        assert _is_hyphenated_slug("_brain-stuff") is False


# ------------------------------------------------------------------
# Unit tests: frontmatter round-trip
# ------------------------------------------------------------------


class TestFrontmatter:
    def test_read_write_roundtrip(self, tmp_path: Path):
        """Frontmatter should survive a read→write cycle."""
        note = tmp_path / "test.md"
        note.write_text(
            textwrap.dedent("""\
            ---
            title: Test Note
            tags:
              - one
              - two
            ---

            Body text here.
            """),
            encoding="utf-8",
        )

        fm, _, body = _read_frontmatter(note)
        assert fm is not None
        assert fm["title"] == "Test Note"
        assert fm["tags"] == ["one", "two"]

        fm["category"] = "Reference"
        _write_frontmatter(note, fm, body)

        fm2, _, body2 = _read_frontmatter(note)
        assert fm2 is not None
        assert fm2["category"] == "Reference"
        assert fm2["title"] == "Test Note"
        assert "Body text" in body2

    def test_no_frontmatter(self, tmp_path: Path):
        note = tmp_path / "plain.md"
        note.write_text("Just a plain file.\n", encoding="utf-8")
        fm, _, _ = _read_frontmatter(note)
        assert fm is None


# ------------------------------------------------------------------
# Integration tests: rename
# ------------------------------------------------------------------


class TestRenameToTitleCase:
    def test_renames_hyphenated_files(self, vault: Path):
        rename_map = rename_to_title_case(vault)

        assert "brain-project-setup" in rename_map
        assert (
            rename_map["brain-project-setup"] == "Brain Project Copier Template Setup"
        )

        # Old file should be gone, new one should exist
        assert not (vault / "Projects" / "brain-project-setup.md").exists()
        assert (vault / "Projects" / "Brain Project Copier Template Setup.md").exists()

    def test_dry_run_does_not_modify(self, vault: Path):
        rename_map = rename_to_title_case(vault, dry_run=True)

        assert len(rename_map) > 0
        # Original file should still exist
        assert (vault / "Projects" / "brain-project-setup.md").exists()

    def test_skips_demo_folder(self, vault: Path):
        rename_to_title_case(vault)
        # Demo files should be untouched
        assert (vault / "Demo" / "millie-dog.md").exists()


# ------------------------------------------------------------------
# Integration tests: wiki-links
# ------------------------------------------------------------------


class TestUpdateWikiLinks:
    def test_updates_links(self, vault: Path):
        rename_map = rename_to_title_case(vault)
        modified = update_wiki_links(vault, rename_map)

        assert modified > 0

        # Check the Actions note had its links updated
        actions_note = vault / "Actions" / "Fix Garden Fence.md"
        text = actions_note.read_text(encoding="utf-8")
        assert "[[Brain Project Copier Template Setup]]" in text
        assert "[[Faithless at Englefield Estate]]" in text
        # Old links should be gone
        assert "[[brain-project-setup]]" not in text
        assert "[[faithless-englefield-estate]]" not in text

    def test_empty_rename_map(self, vault: Path):
        assert update_wiki_links(vault, {}) == 0


# ------------------------------------------------------------------
# Integration tests: fix_frontmatter
# ------------------------------------------------------------------


class TestFixFrontmatter:
    def test_fixes_category_mismatch(self, vault: Path):
        modified = fix_frontmatter(vault)
        assert modified > 0

        # Reference note had category: Inbox — should now be Reference
        ref_note = vault / "Reference" / "android-slack-share-sheet-shortcut.md"
        fm, _, _ = _read_frontmatter(ref_note)
        assert fm is not None
        assert fm["category"] == "Reference"

    def test_adds_missing_fields(self, vault: Path):
        fix_frontmatter(vault)

        # Reference note was missing 'topic' — should have been added
        ref_note = vault / "Reference" / "android-slack-share-sheet-shortcut.md"
        fm, _, _ = _read_frontmatter(ref_note)
        assert fm is not None
        assert "topic" in fm

    def test_dry_run_no_changes(self, vault: Path):
        fix_frontmatter(vault, dry_run=True)

        # Category mismatch should still exist
        ref_note = vault / "Reference" / "android-slack-share-sheet-shortcut.md"
        fm, _, _ = _read_frontmatter(ref_note)
        assert fm is not None
        assert fm["category"] == "Inbox"  # Still wrong
