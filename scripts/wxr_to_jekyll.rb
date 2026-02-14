#!/usr/bin/env ruby
# frozen_string_literal: true

# WordPress WXR to Jekyll migration script for har.center
#
# Converts a WordPress export (WXR XML) into Jekyll posts with:
#   - Filenames: YYYY-MM-DD_circle_event_session-number.md
#   - Front matter: Date, Circle, Event, Session, title, Contacts, Channels, Introduction, Group Questions
#   - Introduction and Group Questions extracted from content into front matter
#
# Usage:
#   ruby scripts/wxr_to_jekyll.rb ~/Downloads/harc_wp.xml
#   ruby scripts/wxr_to_jekyll.rb ~/Downloads/harc_wp.xml --output _posts --dry-run
#
# Prerequisites:
#   bundle install  # installs nokogiri, reverse_markdown
#
# WordPress metadata is read from:
#   - wp:postmeta (custom fields): circle, event, session, contacts, channels, introduction, etc.
#   - categories: Circle/X, Event/Y (parent/child format)
#   - content: parsed for <!--intro-->...<!--/intro-->, # Group question, etc.

require "fileutils"
require "yaml"
require "time"

begin
  require "nokogiri"
rescue LoadError
  abort "Run: bundle install (requires nokogiri and reverse_markdown gems)"
end

begin
  require "reverse_markdown"
rescue LoadError
  abort "Run: bundle install (requires reverse_markdown gem)"
end

# --- Configuration ---

OUTPUT_DIR = "_posts"
CONFIG_PATH = "_config.yml"

# Map display names back to slugs for filenames (reverse of designation_mappings)
def load_reverse_mappings
  return {} unless File.exist?(CONFIG_PATH)
  config = YAML.load_file(CONFIG_PATH)
  mappings = config["designation_mappings"] || {}
  reverse = { circle: {}, event: {} }
  (mappings["circle"] || {}).each { |slug, display| reverse[:circle][display.to_s.downcase] = slug }
  (mappings["event"] || {}).each { |slug, display| reverse[:event][display.to_s.downcase] = slug }
  reverse
end

def to_slug(value)
  return nil if value.to_s.strip.empty?
  s = value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-?\z/, "")
  s.empty? ? nil : s
end

def slug_for(value, field, reverse_mappings)
  return nil if value.to_s.strip.empty?
  v = value.to_s.strip
  slug = to_slug(v)
  rev = reverse_mappings[field] || {}
  rev[v.downcase] || rev[slug&.tr("-", "_")] || slug&.tr("-", "_") || to_slug(v)&.tr("-", "_")
end

# --- Content extraction ---

def extract_intro_and_group_questions(html_content)
  intro = nil
  group_questions = nil
  body = html_content.dup

  # <!--intro-->...<!--/intro--> or <!-- introduction -->...<!-- /introduction -->
  if body =~ /<!--\s*intro(?:duction)?\s*-->(.*?)<!--\s*\/intro(?:duction)?\s*-->/im
    intro = Regexp.last_match(1).strip
    body = body.gsub(/<!--\s*intro(?:duction)?\s*-->.*?<!--\s*\/intro(?:duction)?\s*-->/im, "")
  end

  # <div class="intro">...</div> or similar
  if body =~ /<div[^>]*class="[^"]*intro[^"]*"[^>]*>(.*?)<\/div>/im
    intro ||= Regexp.last_match(1).strip
    body = body.gsub(/<div[^>]*class="[^"]*intro[^"]*"[^>]*>.*?<\/div>/im, "")
  end

  # # Group question or ## Group question (markdown-style in HTML: <h1>Group question</h1>)
  # Capture until next major heading or "channeled message" / "transcript"
  group_patterns = [
    /<h[1-6][^>]*>\s*Group\s+question(s?)\s*<\/h[1-6]>\s*(.*?)(?=<h[1-6]|#\s*Channeled|#\s*Transcript|<p>\s*<strong>We\s+are)/im,
    /(?:^|\n)\s*#\s*Group\s+question(s?)\s*\n\n(.*?)(?=\n#\s|#\s*Channeled|#\s*Transcript|\n\*\*We\s+are)/im,
  ]
  group_patterns.each do |re|
    if body =~ re
      group_questions = Regexp.last_match(2).to_s.strip
      if group_questions && !group_questions.empty?
        body = body.sub(re, "")
        break
      end
    end
  end

  # If content starts with a short paragraph before "We are X" that looks like intro
  unless intro
    if body =~ /\A\s*<p>(.{20,500}?)<\/p>/im
      candidate = Regexp.last_match(1).gsub(/<[^>]+>/, "").strip
      # Intro usually doesn't start with "We are" (channeled greeting)
      intro = candidate if candidate !~ /\AWe\s+are\s+/i && candidate.length < 400
    end
  end

  { intro: intro, group_questions: group_questions, body: body.strip }
end

def html_to_markdown(html)
  return "" if html.to_s.strip.empty?
  # Strip HTML comments before conversion
  html = html.gsub(/<!--.*?-->/m, "")
  ReverseMarkdown.convert(html, unknown_tags: :bypass, github_flavored: true)
rescue StandardError
  html.gsub(/<[^>]+>/, "").gsub(/&nbsp;/, " ")
end

# --- WXR parsing ---

def parse_wxr(path)
  doc = Nokogiri::XML(File.read(path))
  doc.remove_namespaces!
  doc.xpath("//item").select do |item|
    pt = item.xpath("*[local-name()='post_type']").first&.text.to_s.strip
    pt == "post"
  end
end

def get_meta(item, key)
  item.xpath("*[local-name()='postmeta']").each do |pm|
    mk = pm.xpath("*[local-name()='meta_key']").first&.text.to_s
    return pm.xpath("*[local-name()='meta_value']").first&.text if mk.downcase == key.downcase
  end
  nil
end

def get_meta_ci(item, key)
  key_variants = [key, key.downcase, key.capitalize, key.gsub(/_(\w)/) { Regexp.last_match(1).upcase }]
  key_variants.each do |k|
    v = get_meta(item, k)
    return v if v && !v.strip.empty?
  end
  nil
end

def get_categories(item)
  item.xpath("*[local-name()='category']").map { |c| c["nicename"] || c.text }.compact
end

def parse_categories_for_circle_event(categories)
  circle = nil
  event = nil
  categories.each do |cat|
    parts = cat.to_s.split("/")
    next if parts.empty?
    if parts.length >= 2
      parent, child = parts[0].downcase, parts[1]
      circle = child if parent == "circle" || parent == "circles"
      event = child if parent == "event" || parent == "events"
    else
      # Try to infer from single category
      c = cat.to_s.downcase
      circle = cat.to_s if %w[columbus richmond harc colorado-springs].any? { |x| c.include?(x) }
      event = cat.to_s if %w[ccp gm ccp gm training].any? { |x| c.include?(x) }
    end
  end
  [circle, event]
end

def parse_post(item, reverse_mappings)
  title = item.xpath("*[local-name()='title']").first&.text || "Untitled"
  content_el = item.xpath("*[local-name()='encoded']").first
  content = content_el ? content_el.text.to_s : ""

  pub_date = item.xpath("*[local-name()='post_date']").first&.text
  date = pub_date ? Time.parse(pub_date) : nil
  status = item.xpath("*[local-name()='status' or local-name()='post_status']").first&.text
  return nil if status != "publish" && status != "draft"

  # Metadata from custom fields
  meta_circle = get_meta_ci(item, "circle")
  meta_event = get_meta_ci(item, "event")
  meta_session = get_meta_ci(item, "session")
  meta_contacts = get_meta_ci(item, "contacts")
  meta_channels = get_meta_ci(item, "channels")
  meta_intro = get_meta_ci(item, "introduction") || get_meta_ci(item, "intro")
  meta_group_q = get_meta_ci(item, "group_questions") || get_meta_ci(item, "group questions")
  meta_tags = get_meta_ci(item, "tags")
  meta_media = get_meta_ci(item, "media")

  # Categories
  categories = get_categories(item)
  cat_circle, cat_event = parse_categories_for_circle_event(categories)

  circle_raw = meta_circle || cat_circle
  event_raw = meta_event || cat_event
  session_raw = meta_session

  circle = slug_for(circle_raw, :circle, reverse_mappings) || to_slug(circle_raw)&.tr("-", "_")
  event = slug_for(event_raw, :event, reverse_mappings) || to_slug(event_raw)&.tr("-", "_")
  session = session_raw.to_s.strip
  session = session.rjust(3, "0") if session.match?(/^\d+$/)

  # Extract intro and group questions from content
  extracted = extract_intro_and_group_questions(content)
  intro = meta_intro || extracted[:intro]
  group_questions = meta_group_q || extracted[:group_questions]
  body_content = extracted[:body]

  # Skip if we can't build a valid filename
  return nil unless date && circle && event && session

  {
    title: title,
    date: date,
    circle: circle,
    event: event,
    session: session,
    contacts: meta_contacts,
    channels: meta_channels,
    introduction: intro,
    group_questions: group_questions,
    tags: meta_tags,
    media: meta_media,
    body: body_content,
  }
end

def build_filename(post)
  date_str = post[:date].strftime("%Y-%m-%d")
  "#{date_str}_#{post[:circle]}_#{post[:event]}_#{post[:session]}.md"
end

def build_front_matter(post)
  fm = {
    "Date" => post[:date].strftime("%Y-%m-%d"),
    "Circle" => post[:circle],
    "title" => post[:title],
    "Event" => post[:event],
    "Session" => post[:session],
  }
  fm["Contacts"] = post[:contacts] if post[:contacts] && !post[:contacts].strip.empty?
  fm["Channels"] = post[:channels] if post[:channels] && !post[:channels].strip.empty?
  fm["Tags"] = post[:tags] if post[:tags] && !post[:tags].strip.empty?
  fm["Media"] = post[:media] if post[:media] && !post[:media].strip.empty?
  fm["Introduction"] = post[:introduction] if post[:introduction] && !post[:introduction].strip.empty?
  fm["Group Questions"] = post[:group_questions] if post[:group_questions] && !post[:group_questions].strip.empty?
  fm
end

def write_post(post, output_dir, dry_run: false)
  filename = build_filename(post)
  path = File.join(output_dir, filename)

  body_md = html_to_markdown(post[:body])
  body_md = body_md.strip

  fm = build_front_matter(post)
  front_matter = fm.to_yaml(line_width: -1).strip
  content = <<~MD
    ---
    #{front_matter}
    ---


    #{body_md}
  MD

  if dry_run
    puts "[DRY RUN] Would write: #{path}"
    puts "  Circle: #{post[:circle]}, Event: #{post[:event]}, Session: #{post[:session]}"
    return
  end

  FileUtils.mkdir_p(output_dir)
  File.write(path, content)
  puts "Wrote: #{path}"
end

# --- Main ---

def main
  args = ARGV.dup
  dry_run = args.delete("--dry-run")
  output_idx = args.index("--output")
  output_dir = output_idx ? args[output_idx + 1] : OUTPUT_DIR
  args -= ["--output", output_dir] if output_idx

  wxr_path = args.first
  unless wxr_path && File.exist?(wxr_path)
    puts "Usage: ruby scripts/wxr_to_jekyll.rb ~/Downloads/harc_wp.xml [--output _posts] [--dry-run]"
    puts ""
    puts "Export from har.center: Tools → Export → All content → Download"
    exit 1
  end

  reverse_mappings = load_reverse_mappings
  items = parse_wxr(wxr_path)
  puts "Found #{items.size} posts in WXR"

  written = 0
  skipped = 0
  items.each do |item|
    post = parse_post(item, reverse_mappings)
    if post
      write_post(post, output_dir, dry_run: dry_run)
      written += 1
    else
      skipped += 1
    end
  end

  puts ""
  puts "Done. Wrote #{written} posts, skipped #{skipped}."
end

main
