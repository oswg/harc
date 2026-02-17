# frozen_string_literal: true

# Jekyll plugin: Accept underscores in post filenames
# Format: YYYY-MM-DD_circle_event_session-number (e.g. 2024-01-01_richmond_ccp_017.md)
# Patches Document to accept hyphen or underscore between date and title.
# Pattern defined in constants.rb.

if Jekyll::Document.const_defined?(:DATE_FILENAME_MATCHER, false)
  Jekyll::Document.send(:remove_const, :DATE_FILENAME_MATCHER)
end
Jekyll::Document::DATE_FILENAME_MATCHER = Harc::DATE_FILENAME_MATCHER
