#!/usr/bin/env ruby
# frozen_string_literal: true

# Add audio to existing Jekyll posts from a WordPress WXR export.
# - Extracts audio URLs from enclosure elements and postmeta (media, enclosure, etc.)
# - Downloads MP3/M4A files to assets/audio/
# - Adds audio: /assets/audio/filename to each post's front matter
#
# Usage:
#   ruby scripts/add_audio_from_wxr.rb ~/Downloads/harc_wp.xml
#   ruby scripts/add_audio_from_wxr.rb ~/Downloads/harc_wp.xml --dry-run
#   ruby scripts/add_audio_from_wxr.rb ~/Downloads/harc_wp.xml --replace-url harc.otherselvesworking.group=har.center
#   ruby scripts/add_audio_from_wxr.rb ~/Downloads/harc_wp.xml --posts-dir _posts --assets-dir assets/audio
#
# Prerequisites: bundle install (nokogiri)

require "fileutils"
require "open-uri"
require "yaml"
require "time"

begin
  require "nokogiri"
rescue LoadError
  abort "Run: bundle install (requires nokogiri gem)"
end

POSTS_DIR = "_posts"
ASSETS_AUDIO_DIR = "assets/audio"
CONFIG_PATH = "_config.yml"

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
      c = cat.to_s.downcase
      circle = cat.to_s if %w[columbus richmond harc colorado-springs].any? { |x| c.include?(x) }
      event = cat.to_s if %w[ccp gm training].any? { |x| c.include?(x) }
    end
  end
  [circle, event]
end

def extract_audio_url(item, url_replace: nil)
  raw_url = nil

  # 1. RSS enclosure element: <enclosure url="..." type="audio/..." length="..."/>
  item.xpath("*[local-name()='enclosure']").each do |enc|
    url = enc["url"] || enc.attr("url")&.value
    type = (enc["type"] || enc.attr("type")&.value).to_s.downcase
    next unless url && !url.strip.empty?
    if type.include?("audio") || url =~ /\.(mp3|m4a|ogg|wav)(\?|$)/i
      raw_url = url.strip
      break
    end
  end

  # 2. Postmeta: media, audio_url, enclosure, powerpress_embed
  unless raw_url
    %w[media audio_url enclosure powerpress_feed_podcast].each do |key|
      val = get_meta_ci(item, key)
      next unless val && !val.strip.empty?

      # May be a raw URL
      if val =~ %r{\Ahttps?://[^\s<>"']+\.(mp3|m4a|ogg)(\?[^\s<>"']*)?\z}i
        raw_url = val.strip
        break
      end
      # May contain url= in enclosure tag or JSON
      if val =~ /url\s*[=:]\s*["']?([^"'\s>]+\.(?:mp3|m4a|ogg)[^"'\s>]*)["']?/i
        raw_url = Regexp.last_match(1).strip
        break
      end
      # May be a full URL
      if val =~ %r{\b(https?://[^\s<>"']+\.(?:mp3|m4a|ogg)[^\s<>"']*)}i
        raw_url = Regexp.last_match(1).strip
        break
      end
    end
  end

  return nil unless raw_url

  if url_replace
    from_host, to_host = url_replace
    raw_url = raw_url.gsub(from_host, to_host)
  end

  raw_url
end

def parse_wxr_items(path)
  doc = Nokogiri::XML(File.read(path))
  doc.remove_namespaces!
  doc.xpath("//item").select do |item|
    pt = item.xpath("*[local-name()='post_type']").first&.text.to_s.strip
    pt == "post"
  end
end

def item_to_post_key(item, reverse_mappings, url_replace: nil)
  meta_circle = get_meta_ci(item, "circle")
  meta_event = get_meta_ci(item, "event")
  meta_session = get_meta_ci(item, "session")
  categories = get_categories(item)
  cat_circle, cat_event = parse_categories_for_circle_event(categories)

  circle_raw = meta_circle || cat_circle
  event_raw = meta_event || cat_event
  session_raw = meta_session

  circle = slug_for(circle_raw, :circle, reverse_mappings) || to_slug(circle_raw)&.tr("-", "_")
  event = slug_for(event_raw, :event, reverse_mappings) || to_slug(event_raw)&.tr("-", "_")
  session = session_raw.to_s.strip
  session = session.rjust(3, "0") if session.match?(/^\d+$/)

  pub_date = item.xpath("*[local-name()='post_date']").first&.text
  date = pub_date ? Time.parse(pub_date) : nil
  status = item.xpath("*[local-name()='status' or local-name()='post_status']").first&.text
  return nil unless date && circle && event && session
  return nil unless status == "publish" || status == "draft"

  filename = "#{date.strftime('%Y-%m-%d')}_#{circle}_#{event}_#{session}.md"
  { filename: filename, audio_url: extract_audio_url(item, url_replace: url_replace) }
end

require "digest"

def safe_filename_from_url(url)
  begin
    path = URI.parse(url).path
    base = File.basename(path)
    base = base.gsub(/\?.*/, "")
    base = base.gsub(/[^\w.\-]/, "_")
    base = "audio.mp3" if base.empty?
    base << ".mp3" unless base =~ /\.(mp3|m4a|ogg|wav)$/i
    base
  rescue
    "audio_#{Digest::MD5.hexdigest(url)[0, 8]}.mp3"
  end
end

def download_audio(url, dest_path, dry_run: false)
  return true if File.exist?(dest_path)
  return false if dry_run

  URI.open(url, "rb", read_timeout: 60) do |remote|
    File.open(dest_path, "wb") { |f| f.write(remote.read) }
  end
  true
rescue StandardError => e
  warn "  Download failed: #{e.message}"
  false
end

def add_audio_to_front_matter(post_path, audio_path, dry_run: false)
  content = File.read(post_path)
  return false unless content =~ /\A---\n(.*?\n)---\n(.*)/m

  fm_str = Regexp.last_match(1)
  body = Regexp.last_match(2)

  if fm_str =~ /^audio:\s*.+$/m
    return false if fm_str =~ /^audio:\s*#{Regexp.escape(audio_path)}\s*$/m
    new_fm = fm_str.sub(/^audio:\s*.+$/m, "audio: #{audio_path}")
  else
    new_fm = fm_str.rstrip + "\naudio: #{audio_path}\n"
  end

  return false if dry_run

  File.write(post_path, "---\n#{new_fm}---\n#{body}")
  true
end

def main
  args = ARGV.dup
  dry_run = args.delete("--dry-run")
  posts_idx = args.index("--posts-dir")
  posts_dir = posts_idx ? args[posts_idx + 1] : POSTS_DIR
  args -= ["--posts-dir", posts_dir] if posts_idx
  assets_idx = args.index("--assets-dir")
  assets_dir = assets_idx ? args[assets_idx + 1] : ASSETS_AUDIO_DIR
  args -= ["--assets-dir", assets_dir] if assets_idx

  url_replace = nil
  replace_idx = args.index("--replace-url")
  if replace_idx && args[replace_idx + 1]
    pair = args[replace_idx + 1]
    args -= ["--replace-url", pair]
    if pair =~ /^(.+)=(.+)$/
      url_replace = [Regexp.last_match(1), Regexp.last_match(2)]
      puts "Replacing URL host: #{url_replace[0]} -> #{url_replace[1]}"
    end
  end

  wxr_path = args.first
  unless wxr_path && File.exist?(wxr_path)
    puts "Usage: ruby scripts/add_audio_from_wxr.rb ~/Downloads/harc_wp.xml [--posts-dir _posts] [--assets-dir assets/audio] [--replace-url FROM=TO] [--dry-run]"
    puts ""
    puts "Export from har.center: Tools → Export → All content → Download"
    exit 1
  end

  unless File.directory?(posts_dir)
    puts "Posts directory not found: #{posts_dir}"
    exit 1
  end

  reverse_mappings = load_reverse_mappings
  items = parse_wxr_items(wxr_path)
  puts "Found #{items.size} posts in WXR"

  FileUtils.mkdir_p(assets_dir) unless dry_run

  updated = 0
  downloaded = 0
  skipped_no_audio = 0
  skipped_no_post = 0

  items.each do |item|
    entry = item_to_post_key(item, reverse_mappings, url_replace: url_replace)
    next unless entry

    filename = entry[:filename]
    audio_url = entry[:audio_url]

    unless audio_url
      skipped_no_audio += 1
      next
    end

    post_path = File.join(posts_dir, filename)
    unless File.exist?(post_path)
      skipped_no_post += 1
      next
    end

    local_basename = safe_filename_from_url(audio_url)
    local_path = File.join(assets_dir, local_basename)
    audio_path = "/#{assets_dir}/#{local_basename}"

    if File.exist?(local_path)
      # Already have the file, just ensure front matter is updated
    else
      if download_audio(audio_url, local_path, dry_run: dry_run)
        downloaded += 1 unless dry_run
        puts "#{dry_run ? '[DRY RUN] Would download' : 'Downloaded'} #{local_basename}"
      else
        next # Skip front matter update if download failed
      end
    end

    if add_audio_to_front_matter(post_path, audio_path, dry_run: dry_run)
      updated += 1
      puts "#{dry_run ? '[DRY RUN] Would add audio to' : 'Updated'} #{filename}"
    end
  end

  puts ""
  puts "Done. Downloaded #{downloaded} files, updated #{updated} posts."
  puts "Skipped #{skipped_no_audio} (no audio in WXR), #{skipped_no_post} (no matching post file)." if (skipped_no_audio + skipped_no_post) > 0
end

main
