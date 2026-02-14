#!/usr/bin/env ruby
# frozen_string_literal: true

# Rename post files from long-form slugs to short-form slugs.
# Uses designation_mappings from _config.yml for the canonical short forms.
#
# Mappings (long → short):
#   Circle: the_harc_circle, harc_circle → harc
#   Event: confederation_channelling_practice, confederation_channeling_practice → ccp
#   Event: working_group_gathering_24 → gathering-24
#
# Usage: ruby scripts/rename_to_short_slugs.rb [_posts]
#        ruby scripts/rename_to_short_slugs.rb --dry-run

require "fileutils"

POSTS_DIR = "_posts"

# Long-form slug → short-form slug (replace in filename; order matters)
# Order matters: replace longer strings first (e.g. the_harc_circle before harc_circle).
ALL_LONG_TO_SHORT = [
  ["the_harc_circle", "harc"],
  ["harc_circle", "harc"],
  ["confederation_channelling_practice", "ccp"],
  ["confederation_channeling_practice", "ccp"],
  ["working_group_gathering_24", "gathering-24"],
].freeze

def build_new_filename(basename)
  return nil unless basename =~ /\A(\d{4}-\d{2}-\d{2})[-_](.+)\z/
  date_part = Regexp.last_match(1)
  slug = Regexp.last_match(2)
  # Session is trailing digits, or empty (use "001")
  m = slug.match(/^(.+)_(\d*)$/)
  return nil unless m
  middle = m[1]
  session = m[2].empty? ? "001" : m[2]

  short = middle.dup
  ALL_LONG_TO_SHORT.each { |long, s| short.gsub!(long, s) }
  return nil if short == middle  # no changes

  "#{date_part}_#{short}_#{session}"
end

def main
  args = ARGV.dup
  dry_run = args.delete("--dry-run")
  dir = args.first || POSTS_DIR

  unless File.directory?(dir)
    puts "Usage: ruby scripts/rename_to_short_slugs.rb [_posts] [--dry-run]"
    exit 1
  end

  renamed = 0
  Dir[File.join(dir, "*.md")].sort.each do |path|
    basename = File.basename(path, ".*")
    new_base = build_new_filename(basename)
    next unless new_base && new_base != basename

    new_path = File.join(dir, "#{new_base}.md")
    if File.exist?(new_path) && new_path != path
      warn "Skip (target exists): #{basename}.md -> #{new_base}.md"
      next
    end

    if dry_run
      puts "[DRY RUN] #{basename}.md -> #{new_base}.md"
    else
      FileUtils.mv(path, new_path)
      puts "Renamed: #{basename}.md -> #{new_base}.md"
    end
    renamed += 1
  end

  puts "\nRenamed #{renamed} posts."
end

main
