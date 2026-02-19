#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare WordPress WXR export content against Jekyll _posts.
# Flags posts where the body text is COMPLETELY different (not minor edits).
#
# Usage: ruby scripts/compare_wp_to_posts.rb [path/to/harc_wp.xml]

require "nokogiri"
require "pathname"

POSTS_DIR = Pathname(__dir__).join("../_posts").expand_path
XML_PATH = if ARGV[0]
  Pathname(ARGV[0]).expand_path
else
  Pathname(__dir__).join("../harc_wp.xml").expand_path
end

# Map WP meta values to Jekyll filename slugs
EVENT_TO_SLUG = {
  "First Channeling Intensive" => "ci1",
  "Second Channeling Intensive" => "ci2",
  "Third Channeling Intensive" => "ci3",
  "Fourth Channeling Intensive" => "ci4",
  "Fifth Channeling Intensive" => "ci5",
  "Sixth Channeling Intensive" => "ci6",
  "Confederation Channeling Practice" => "ccp",
  "Confederation Channelling Practice" => "ccp",
  "Gathering '24" => "gathering-24",
  "Working Group Gathering '24" => "gathering-24",
  "2025 Invitational" => "2025-invitational",
}.freeze

CIRCLE_TO_SLUG = {
  "The HARC Circle" => "harc",
  "The High Altitude Receiving Center (HARC) Circle" => "harc",
  "Richmond Meditation Circle" => "richmond",
  "Colorado Springs Circle" => "colorado-springs",
}.freeze

def slugify(s)
  s.to_s.downcase.gsub(/[''`]/, "").gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
end

def normalize_text(raw)
  # Strip HTML/markdown, collapse whitespace, lowercase for comparison
  return "" if raw.nil? || raw.empty?
  text = raw.dup
  # Remove HTML
  text.gsub!(/<[^>]+>/, " ")
  # Remove markdown links [text](url)
  text.gsub!(/\[([^\]]+)\]\([^)]+\)/, "\\1")
  # Remove markdown emphasis/strong but keep the words
  text.gsub!(/[*_]+([^*_]+)[*_]+/, "\\1")
  # Decode entities
  text.gsub!(/&nbsp;/, " ")
  text.gsub!(/&amp;/, "&")
  text.gsub!(/&lt;/, "<")
  text.gsub!(/&gt;/, ">")
  text.gsub!(/&#(\d+);/) { |m| [Regexp.last_match(1).to_i].pack("U") rescue m }
  # Collapse whitespace
  text.gsub!(/\s+/, " ").strip
  text
end

def extract_body_from_md(path)
  content = File.read(path)
  # Strip front matter
  content = content.sub(/\A---\r?\n.*?\r?\n---\r?\n/m, "")
  content
end

def word_overlap_ratio(a_norm, b_norm)
  return 0.0 if a_norm.empty? || b_norm.empty?
  a_words = a_norm.split(/\s+/).reject { |w| w.length < 3 }.uniq
  b_words = b_norm.split(/\s+/).reject { |w| w.length < 3 }.uniq
  return 0.0 if a_words.empty? || b_words.empty?
  overlap = (a_words & b_words).size
  # Ratio of overlapping words to the smaller set's size
  [overlap.to_f / a_words.size, overlap.to_f / b_words.size].min
end

# Build lookup: "date_circle_event_session" -> post path
def jekyll_post_index
  index = {}
  POSTS_DIR.glob("*.md").each do |path|
    basename = path.basename(".md").to_s
    next unless basename.match?(/\A\d{4}-\d{2}-\d{2}_/)
    index[basename] = path
  end
  index
end

def main
  abort "XML not found: #{XML_PATH}" unless XML_PATH.exist?
  abort "Posts dir not found: #{POSTS_DIR}" unless POSTS_DIR.directory?

  doc = Nokogiri::XML(File.read(XML_PATH))
  doc.remove_namespaces!

  jekyll_index = jekyll_post_index
  mismatches = []
  matched = 0
  wp_only = 0
  jekyll_only = jekyll_index.keys

  doc.xpath("//item").each do |item|
    post_type = item.at_xpath("post_type")&.text
    status = item.at_xpath("status")&.text
    next unless post_type == "post" && status == "publish"

    title = item.at_xpath("title")&.text
    content_el = item.at_xpath(".//*[local-name()='encoded']")
    content_enc = content_el ? content_el.text.to_s : ""
    post_name = item.at_xpath("post_name")&.text

    # Extract meta
    meta = {}
    item.xpath("postmeta").each do |pm|
      k = pm.at_xpath("meta_key")&.text
      v = pm.at_xpath("meta_value")&.text
      meta[k] = v if k && v
    end

    date = meta["date"]&.strip
    session = meta["session"]&.strip
    event = meta["event"]&.strip
    circle = (meta["circle"] || meta["circle_slug"])&.strip

    next if date.to_s.empty? || session.to_s.empty?
    next if content_enc.strip.empty? # skip intro-only or placeholder posts

    event_slug = EVENT_TO_SLUG[event] || slugify(event.to_s)
    circle_slug = CIRCLE_TO_SLUG[circle] || slugify(circle.to_s)

    # Jekyll format: YYYY-MM-DD_circle_event_NNN
    session_padded = session.to_s.rjust(3, "0")
    jekyll_key = "#{date}_#{circle_slug}_#{event_slug}_#{session_padded}"

    jekyll_path = jekyll_index[jekyll_key]
    if jekyll_path.nil?
      # Try without circle for 2-part filenames (e.g. richmond_ccp_017)
      alt_key = "#{date}_#{event_slug}_#{session_padded}"
      jekyll_path = jekyll_index[alt_key]
    end

    if jekyll_path.nil?
      wp_only += 1
      mismatches << {
        type: :wp_only,
        wp_title: title,
        wp_link: item.at_xpath("link")&.text,
        jekyll_key: jekyll_key,
        reason: "No matching Jekyll post",
      }
      next
    end

    jekyll_only.delete(jekyll_key)

    jekyll_body = extract_body_from_md(jekyll_path)
    wp_body = content_enc

    # Skip intro/boilerplate - compare the channeled message portion
    # WP often has "Introduction" and "Channeled message" headings; we want the body
    wp_norm = normalize_text(wp_body)
    jekyll_norm = normalize_text(jekyll_body)

    overlap = word_overlap_ratio(wp_norm, jekyll_norm)

    # Completely different: < 25% word overlap
    if overlap < 0.25
      mismatches << {
        type: :different_content,
        wp_title: title,
        wp_link: item.at_xpath("link")&.text,
        jekyll_file: jekyll_path.basename.to_s,
        overlap: (overlap * 100).round(1),
        wp_preview: wp_norm[0..150] + "...",
        jekyll_preview: jekyll_norm[0..150] + "...",
      }
    else
      matched += 1
    end
  end

  puts "=== WP vs Jekyll content comparison ==="
  puts "Matched (same or similar content): #{matched}"
  puts ""

  different = mismatches.select { |m| m[:type] == :different_content }
  if different.any?
    puts "⚠️  COMPLETELY DIFFERENT CONTENT (#{different.size}):"
    puts ""
    different.each do |m|
      puts "  WP: #{m[:wp_title]}"
      puts "  WP link: #{m[:wp_link]}"
      puts "  Jekyll: #{m[:jekyll_file]}"
      puts "  Word overlap: #{m[:overlap]}%"
      puts "  WP starts: #{m[:wp_preview]}"
      puts "  Jekyll starts: #{m[:jekyll_preview]}"
      puts ""
    end
  end

  wp_only_list = mismatches.select { |m| m[:type] == :wp_only }
  if wp_only_list.any?
    puts "WP posts with no Jekyll match (#{wp_only_list.size}):"
    wp_only_list.each do |m|
      puts "  #{m[:wp_title]} (#{m[:wp_link]})"
    end
    puts ""
  end

  if jekyll_only.any?
    puts "Jekyll posts with no WP match (#{jekyll_only.size}): #{jekyll_only.first(10).join(", ")}#{"..." if jekyll_only.size > 10}"
  end
end

main
