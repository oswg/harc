#!/usr/bin/env ruby
# frozen_string_literal: true

# Fix misformatted front matter in Jekyll posts migrated from WordPress.
#
# Fixes:
#   1. Duplicate --- at start of front matter
#   2. Group Questions containing raw WordPress block HTML → plain text
#   3. Circle: the_harc_circle → harc
#   4. ## Introduction section in body → move to Introduction front matter
#   5. Remove all HTML comments from body
#
# Usage: ruby scripts/fix_front_matter.rb [_posts]
#        ruby scripts/fix_front_matter.rb --dry-run

require "fileutils"
require "yaml"

POSTS_DIR = "_posts"

def strip_wp_block_html(text)
  return "" if text.to_s.strip.empty?
  # Remove WordPress block comments
  t = text.gsub(/<!--\s*\/?wp:[^>]*-->/i, "")
  # Strip HTML tags, decode entities
  t = t.gsub(/<p[^>]*>(.*?)<\/p>/im, "\\1\n")
  t = t.gsub(/<[^>]+>/, "")
  t = t.gsub(/&nbsp;/, " ")
  t = t.gsub(/&amp;/, "&").gsub(/&lt;/, "<").gsub(/&gt;/, ">").gsub(/&quot;/, '"')
  t = t.gsub(/\n{3,}/, "\n\n").strip
  t
end

def extract_intro_from_body(content)
  return [nil, content] unless content =~ /^##\s+Introduction\s*$/i
  # Find content between ## Introduction and next ## heading
  if content =~ /^##\s+Introduction\s*\n+(.*?)(?=^##\s+|\z)/im
    intro_text = Regexp.last_match(1).strip
    body_without = content.sub(/^##\s+Introduction\s*\n+.*?(?=^##\s+|\z)/im, "").strip
    [intro_text, body_without]
  else
    [nil, content]
  end
end

def fix_post(path, dry_run: false)
  raw = File.read(path)
  return unless raw.start_with?("---")

  # Split: --- (optional duplicate) ... YAML ... ---  body
  if raw =~ /\A---\s*\n(?:---\s*\n)?(.*?)---\s*\n\n*(.*)/m
    fm_raw = Regexp.last_match(1).strip
    body = Regexp.last_match(2)
  else
    return
  end

  begin
    fm = YAML.safe_load(fm_raw)
  rescue Psych::SyntaxError => e
    warn "YAML error in #{path}: #{e.message}"
    return
  end

  return unless fm.is_a?(Hash)

  changed = false

  # 1. Fix Circle: the_harc_circle → harc
  if fm["Circle"].to_s == "the_harc_circle"
    fm["Circle"] = "harc"
    changed = true
  end

  # 2. Fix Date/Session quotes (YAML loads them as strings; we want clean format on write)
  # We'll output without quotes when writing

  # 3. Fix Group Questions - strip WP HTML
  if fm["Group Questions"]
    gq = fm["Group Questions"]
    cleaned = strip_wp_block_html(gq.to_s)
    if cleaned != gq.to_s.strip
      fm["Group Questions"] = cleaned.empty? ? nil : cleaned
      changed = true
    end
  end

  # 4. Move ## Introduction from body to front matter
  intro_from_body, new_body = extract_intro_from_body(body)
  if intro_from_body && (fm["Introduction"].to_s.strip.empty? || fm["Introduction"] == intro_from_body)
    fm["Introduction"] = intro_from_body
    body = new_body
    changed = true
  elsif intro_from_body && !fm["Introduction"].to_s.strip.empty?
    # Intro already in FM, just remove from body
    body = new_body
    changed = true
  end

  # 5. Remove all HTML comments from body
  body_no_comments = body.gsub(/<!--.*?-->/m, "")
  body_no_comments = body_no_comments.gsub(/\n{3,}/, "\n\n").strip
  if body_no_comments != body
    body = body_no_comments
    changed = true
  end

  # 6. Output clean front matter (no leading --- from to_yaml)
  # Build clean output
  fm.delete(nil)
  fm.each { |k, v| fm.delete(k) if v.to_s.strip.empty? && k != "Tags" && k != "Media" }

  output_fm = fm.to_yaml(line_width: -1).sub(/\A---\s*\n/, "")
  output = <<~MD
    ---
    #{output_fm.strip}
    ---


    #{body.strip}
  MD

  return if output == raw && !dry_run

  if dry_run
    puts "[DRY RUN] Would fix: #{path}"
    return
  end

  File.write(path, output)
  puts "Fixed: #{path}"
end

def main
  args = ARGV.dup
  dry_run = args.delete("--dry-run")
  dir = args.first || POSTS_DIR

  unless File.directory?(dir)
    puts "Usage: ruby scripts/fix_front_matter.rb [_posts] [--dry-run]"
    exit 1
  end

  count = 0
  Dir[File.join(dir, "*.md")].sort.each do |path|
    fix_post(path, dry_run: dry_run)
    count += 1
  end
  puts "\nProcessed #{count} posts."
end

main
