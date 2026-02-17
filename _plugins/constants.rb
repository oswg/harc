# frozen_string_literal: true

# All HARC plugin constants. Loads first (alphabetically) so other plugins reference Harc::*.
# Prevents duplicate-constant warnings and keeps configuration in one place.

module Harc
  # Post filenames: YYYY-MM-DD_circle_event_session (accepts hyphen or underscore after date)
  DATE_FILENAME_MATCHER = %r!\A(?>.+/)*?(\d{2,4}-\d{1,2}-\d{1,2})[-_]([^/]*)(\.[^.]+)\z!.freeze

  # Event name → slug for category URLs (e.g. "first-channeling-intensive" => "ci1")
  EVENT_CI_SLUGS = {
    "first-channeling-intensive" => "ci1",
    "second-channeling-intensive" => "ci2",
    "third-channeling-intensive" => "ci3",
    "fourth-channeling-intensive" => "ci4",
    "fifth-channeling-intensive" => "ci5",
    "sixth-channeling-intensive" => "ci6",
  }.freeze

  # Circle slug overrides for permalinks (e.g. "harc_circle" → "harc")
  CIRCLE_SLUG_OVERRIDES = { "harc_circle" => "harc" }.freeze

  # Category parents shown in sidebar (order matters)
  SIDEBAR_PARENTS = %w[Circles Topics Events Contacts Instruments].freeze
end
