# frozen_string_literal: true

# Jekyll plugin: Accept underscores in post filenames
# Format: YYYY-MM-DD_circle_event_session-number (e.g. 2024-01-01_richmond_ccp_017.md)
#
# Jekyll normally requires a hyphen between the date and title. This patches
# Document to accept either hyphen or underscore as the separator.
# Note: A "already initialized constant" warning on build is expected and harmless.

Jekyll::Document::DATE_FILENAME_MATCHER = %r!\A(?>.+/)*?(\d{2,4}-\d{1,2}-\d{1,2})[-_]([^/]*)(\.[^.]+)\z!.freeze
