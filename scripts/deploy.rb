#!/usr/bin/env ruby
# frozen_string_literal: true

# Deploy script: create stub posts for new MP3s, upload audio to S3, update frontmatter, push to origin main.
#
# For MP3s without a matching post: prompts for instrument, contact, and topic; creates a stub post
# with transcribe: true, uploads to S3, and commits with a descriptive message. The CI workflow
# will then transcribe those posts.
#
# For existing posts with transcribe: true and local audio refs: uploads to S3 and updates frontmatter.
#
# Prerequisites:
#   - AWS CLI configured (aws configure) with credentials that can write to the bucket
#   - MP3 files locally in assets/audio/ (they are gitignored)
#
# Usage:
#   HARC_S3_BUCKET=my-bucket ruby scripts/deploy.rb
#   HARC_S3_BUCKET=my-bucket HARC_S3_PREFIX=audio HARC_S3_REGION=us-east-1 ruby scripts/deploy.rb
#   HARC_S3_BUCKET=my-bucket ruby scripts/deploy.rb --dry-run
#   HARC_S3_BUCKET=my-bucket ruby scripts/deploy.rb --no-push
#
# Env vars:
#   HARC_S3_BUCKET   (required) S3 bucket name
#   HARC_S3_PREFIX   (default: audio) Object key prefix, e.g. "harc/audio"
#   HARC_S3_REGION   (default: us-east-1, or AWS_REGION if set) AWS region
#
# Options:
#   --dry-run   Upload and update frontmatter but don't commit or push
#   --no-push   Commit changes but don't push to origin

POSTS_DIR = "_posts"
ASSETS_AUDIO = "assets/audio"

def s3_bucket
  ENV["HARC_S3_BUCKET"]&.strip.tap { |b| abort "Set HARC_S3_BUCKET (e.g. export HARC_S3_BUCKET=my-bucket)" if b.to_s.empty? }
end

def s3_prefix
  (ENV["HARC_S3_PREFIX"] || "audio").strip.chomp("/")
end

def s3_region
  ENV["HARC_S3_REGION"] || ENV["AWS_REGION"] || "us-east-1"
end

def s3_url_for(key)
  # Virtual-hosted-style: https://bucket.s3.region.amazonaws.com/key
  "https://#{s3_bucket}.s3.#{s3_region}.amazonaws.com/#{key}"
end

def local_path?(audio_val)
  return false if audio_val.to_s.strip.empty?
  v = audio_val.to_s.strip
  v.start_with?("/assets/audio/", "assets/audio/") || (v.include?(".mp3") && !v.start_with?("http"))
end

def filename_from_audio_path(audio_val)
  v = audio_val.to_s.strip.gsub(/^["']|["']$/, "")
  v = v.delete_prefix("/")
  v = v.delete_prefix("assets/audio/")
  v.split("/").last || v
end

def collect_audio_refs
  refs = {}
  Dir["#{POSTS_DIR}/*.md"].each do |path|
    content = File.read(path)
    next unless content =~ /\A---\s*\n(.*?)---\s*\n/m
    fm = Regexp.last_match(1)
    # Match audio: "value" or audio: value (single line only)
    if fm =~ /^audio:\s*["']?([^"'\n]+\.mp3)["']?\s*$/m
      val = Regexp.last_match(1).strip
      # Normalize to path-like form for local_path? check
      val = "/assets/audio/#{val}" unless val.include?("/")
      refs[path] = val if val && !val.empty?
    end
  end
  refs
end

def orphan_mp3s
  return [] unless Dir.exist?(ASSETS_AUDIO)
  existing_posts = Dir["#{POSTS_DIR}/*.md"].map { |p| File.basename(p, ".md") }
  Dir["#{ASSETS_AUDIO}/*.mp3"].map do |mp3_path|
    basename = File.basename(mp3_path, ".mp3")
    basename if !existing_posts.include?(basename)
  end.compact.sort
end

def to_sentence(arr)
  case arr.size
  when 0 then ""
  when 1 then arr[0]
  when 2 then "#{arr[0]} and #{arr[1]}"
  else "#{arr[0..-2].join(", ")}, and #{arr.last}"
  end
end

def create_stub_post(post_filename, contact:, instrument:, topic:, audio_url:, dry_run:)
  contacts = contact.to_s.split(",").map(&:strip).reject(&:empty?)
  instruments = instrument.to_s.split(",").map(&:strip).reject(&:empty?)
  contacts_phrase = contacts.any? ? to_sentence(contacts) : "Unknown"
  title = "#{contacts_phrase} on #{topic}"
  categories = [
    "Circles/The High Altitude Receiving Center (HARC) Circle",
    *contacts.map { |name| "Contacts/#{name}" },
    *instruments.map { |name| "Instruments/#{name}" },
    "Topics/#{topic}"
  ]
  lines = [
    "---",
    "title: \"#{title.gsub('"', '\\"')}\"",
    "categories:",
    *categories.map { |c| "- #{c}" },
    "audio: \"#{audio_url}\"",
    "transcribe: true",
    "---",
    ""
  ]
  content = lines.join("\n")

  post_path = File.join(POSTS_DIR, post_filename)
  return false if dry_run
  File.write(post_path, content)
  true
end

def prompt_for_new_post(mp3_basename)
  puts "\nNew MP3 without post: #{mp3_basename}.mp3"
  print "  Contact (comma-separated, e.g. Q'uo, Laitos): "
  contact = $stdin.gets&.strip
  print "  Instrument (comma-separated, e.g. Jeremy, Steve): "
  instrument = $stdin.gets&.strip
  print "  Topic (e.g. Purifying Desire): "
  topic = $stdin.gets&.strip
  [contact, instrument, topic]
end

def upload_to_s3(local_file, s3_key, dry_run:)
  return true if dry_run
  region_arg = s3_region == "us-east-1" ? "" : " --region #{s3_region}"
  cmd = "aws s3 cp #{Shellwords.escape(local_file)} s3://#{s3_bucket}/#{s3_key}#{region_arg}"
  output = `#{cmd} 2>&1`
  success = $?.success?
  warn output unless success
  success
end

def update_frontmatter_audio(post_path, new_url, dry_run:)
  content = File.read(post_path)
  return false unless content =~ /\A---\n(.*?\n)---\n(.*)/m

  fm_str = Regexp.last_match(1)
  body = Regexp.last_match(2)

  # Preserve quoting style; use quotes for URLs. Keep newline after audio line.
  new_val = new_url.include?(":") ? "\"#{new_url}\"" : new_url
  new_fm = fm_str.sub(/^audio:\s*.+$/m, "audio: #{new_val}\n")

  return false if dry_run

  File.write(post_path, "---\n#{new_fm}---\n#{body}")
  true
end

require "shellwords"

def main
  dry_run = ARGV.delete("--dry-run")
  no_push = ARGV.delete("--no-push")

  bucket = s3_bucket
  prefix = s3_prefix
  region = s3_region

  puts "HARC_S3_BUCKET=#{bucket} HARC_S3_PREFIX=#{prefix} HARC_S3_REGION=#{region}"
  puts "(dry-run)" if dry_run
  puts "(no-push)" if no_push
  puts

  refs = collect_audio_refs
  to_upload = refs.select { |_path, val| local_path?(val) }

  # ---- Phase 1: Orphan MP3s (no post yet) ----
  orphans = orphan_mp3s
  orphans.each do |mp3_basename|
    contact, instrument, topic = prompt_for_new_post(mp3_basename)
    if [contact, instrument, topic].any? { |v| v.nil? || v.strip.empty? }
      puts "  Skipping: missing contact, instrument, or topic."
      next
    end

    local_file = File.join(ASSETS_AUDIO, "#{mp3_basename}.mp3")
    s3_key = prefix.empty? ? "#{mp3_basename}.mp3" : "#{prefix}/#{mp3_basename}.mp3"

    print "  Upload #{mp3_basename}.mp3 -> s3://#{bucket}/#{s3_key} ... "
    unless upload_to_s3(local_file, s3_key, dry_run: dry_run)
      puts "FAILED"
      next
    end
    puts "OK"

    url = s3_url_for(s3_key)
    post_filename = "#{mp3_basename}.md"
    if create_stub_post(post_filename, contact: contact, instrument: instrument, topic: topic, audio_url: url, dry_run: dry_run)
      puts "  Created #{POSTS_DIR}/#{post_filename}"
    end

    next if dry_run || no_push

    # Commit this new post
    commit_msg = "Creating #{post_filename} from #{url} about #{contact} on #{topic} via #{instrument}"
    system("git add #{POSTS_DIR}/#{post_filename}", out: $stdout, err: $stderr)
    system("git", "commit", "-m", commit_msg, out: $stdout, err: $stderr)
  end

  # Push Phase 1 commits if we have any (orphans created)
  if orphans.any? && !dry_run && !no_push
    system("git push origin main", out: $stdout, err: $stderr) || abort("git push failed")
    puts "Pushed to origin main."
    return if to_upload.empty?
  end

  # ---- Phase 2: Existing posts with local audio refs ----
  already_remote = refs.select { |_path, val| !local_path?(val) }

  if already_remote.any?
    puts "Skipping #{already_remote.size} post(s) with non-local audio URLs"
  end

  if to_upload.empty?
    puts "No posts with local audio to upload."
    exit 0
  end

  uploads_done = 0
  updates_done = 0

  to_upload.each do |post_path, audio_val|
    filename = filename_from_audio_path(audio_val)
    local_file = File.join(ASSETS_AUDIO, filename)
    s3_key = prefix.empty? ? filename : "#{prefix}/#{filename}"

    unless File.exist?(local_file)
      warn "  Skip #{post_path}: local file missing: #{local_file}"
      next
    end

    print "  Upload #{filename} -> s3://#{bucket}/#{s3_key} ... "
    if upload_to_s3(local_file, s3_key, dry_run: dry_run)
      puts "OK"
      uploads_done += 1
    else
      puts "FAILED"
      next
    end

    url = s3_url_for(s3_key)
    if update_frontmatter_audio(post_path, url, dry_run: dry_run)
      updates_done += 1
    end
  end

  puts
  puts "Uploaded #{uploads_done} file(s), updated #{updates_done} post(s)." if to_upload.any?

  return if dry_run || no_push
  return if updates_done == 0

  # Stop tracking MP3s if they're currently in git (first migration)
  tracked_mp3 = `git ls-files assets/audio/*.mp3 2>/dev/null`.strip
  if !tracked_mp3.empty?
    puts "Removing #{tracked_mp3.lines.size} MP3(s) from git tracking..."
    system("git rm --cached assets/audio/*.mp3 2>/dev/null", out: $stdout, err: $stderr)
  end

  # Git add, commit, push (Phase 2 updates)
  system("git add #{POSTS_DIR} .gitignore && git status", out: $stdout, err: $stderr) || abort("git add failed")
  return if `git status --porcelain #{POSTS_DIR}`.strip.empty?

  system("git commit -m 'Deploy: point audio to S3'", out: $stdout, err: $stderr) || abort("git commit failed")
  system("git push origin main", out: $stdout, err: $stderr) || abort("git push failed")
  puts "Pushed to origin main."
end

main
