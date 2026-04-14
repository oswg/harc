#!/usr/bin/env ruby
# frozen_string_literal: true

# For each post, resolve the same audio URL the site uses and send HTTP HEAD
# (GET with Range fallback). Lists posts whose audio does not return 200/206.
#
# Resolution matches _plugins/audio_url_filter.rb:
# - audio or media in front matter: use as override (absolute URL as-is;
#   site-relative paths use basename joined to audio_base_url from _config.yml)
# - otherwise: {audio_base_url}/{post_basename}.mp3
#
# Usage:
#   ruby scripts/check_audio_links.rb
#   ruby scripts/check_audio_links.rb --verbose   # print every post and status
#
# Exit 1 if any post is missing or errored (for CI).

require "net/http"
require "pathname"
require "uri"
require "yaml"

REPO_ROOT = Pathname.new(__dir__).join("..").expand_path

def load_audio_base
  cfg = YAML.safe_load(
    File.read(REPO_ROOT.join("_config.yml")),
    permitted_classes: [Date, Time],
    aliases: true
  )
  cfg["audio_base_url"].to_s.strip
end

def parse_front_matter(path)
  body = File.read(path)
  return nil unless body.start_with?("---\n")

  idx = body.index("\n---\n", 4)
  return nil unless idx

  YAML.safe_load(
    body[4...idx],
    permitted_classes: [Date, Time],
    aliases: true
  )
end

# Mirrors Jekyll::AudioUrlFilter#post_audio_href (default + override rules).
def resolve_audio_url(post_path, fm, audio_base)
  raw = fm["audio"] || fm["media"]
  raw = raw.to_s.strip

  unless raw.empty?
    return raw if raw.include?("://")

    file = raw.split("/").last
    return nil if audio_base.empty?

    return "#{audio_base.chomp("/")}/#{file}"
  end

  stem = File.basename(post_path, ".md")
  return nil if stem.empty?
  return nil if audio_base.empty?

  "#{audio_base.chomp("/")}/#{stem}.mp3"
end

def http_check(url)
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == "https")
  http.open_timeout = 15
  http.read_timeout = 20

  path = uri.request_uri
  res = http.request(Net::HTTP::Head.new(path))
  code = res.code

  if %w[405 501].include?(code)
    get = Net::HTTP::Get.new(path)
    get["Range"] = "bytes=0-0"
    res = http.request(get)
    code = res.code
  end

  code
rescue StandardError => e
  "ERR:#{e.class}:#{e.message}"
end

def ok_status?(code)
  code == "200" || code == "206"
end

def main
  verbose = ARGV.include?("--verbose")
  audio_base = load_audio_base
  posts = Dir.glob(REPO_ROOT.join("_posts/**/*.md")).sort
  missing = []
  skipped = []

  posts.each do |abs_path|
    rel = Pathname(abs_path).relative_path_from(REPO_ROOT).to_s
    fm = parse_front_matter(abs_path)
    unless fm.is_a?(Hash)
      skipped << rel
      next
    end

    url = resolve_audio_url(abs_path, fm, audio_base)
    if url.nil?
      skipped << rel
      warn "skip #{rel} (no resolvable URL; is audio_base_url set?)" if verbose
      next
    end

    code = http_check(url)
    puts "#{code.ljust(4)}  #{rel}" if verbose

    next if ok_status?(code)

    missing << { rel: rel, url: url, code: code }
  end

  unless skipped.empty?
    puts "Skipped #{skipped.size} post(s) (unreadable or no URL)." if verbose && !skipped.empty?
  end

  puts
  if missing.empty?
    puts "OK: all #{posts.size - skipped.size} checked post(s) returned 200/206 for audio."
  else
    puts "Missing or bad audio (#{missing.size} post(s)):"
    missing.each do |m|
      puts "  #{m[:rel]}"
      puts "    [#{m[:code]}] #{m[:url]}"
    end
    exit 1
  end
end

main
