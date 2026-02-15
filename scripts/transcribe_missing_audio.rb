#!/usr/bin/env ruby
# frozen_string_literal: true

# Find posts with transcribe: true, download their audio from the frontmatter URL,
# transcribe, put the transcript in the body, and remove transcribe: true.
# Used by the transcribe-missing-audio GitHub Action.
#
# Usage:
#   OPENAI_API_KEY=xxx ruby scripts/transcribe_missing_audio.rb
#   OPENAI_API_KEY=xxx ruby scripts/transcribe_missing_audio.rb --dry-run
#
# Env:
#   OPENAI_API_KEY   (required)

require "openai"
require "shellwords"
require "tmpdir"

POSTS_DIR = "_posts"

# Reuse transcription logic from transcribe.rb
module Transcriber
  CHANNELING_PROMPT = <<~TEXT.freeze
    You are an editor of information received from entities in the
    Confederation of Planets in Service to the One Infinite Creator. Please
    review material from High Altitude Receiving Center, and format the sentence
    and paragraph structure like theirs. In addition, pay attention to the name
    of the contact and ensure it's one of these: Q'uo, Hatonn, Laitos, Monka,
    Oorkas, Auxhall. Pay attention also to when the speaker changes if you can
    and make a small note. Finally, break things up into cogent paragraphs that
    improve readability.
  TEXT

  def self.call(mp3_path)
    puts "OPENAI_API_KEY=#{ENV["OPENAI_API_KEY"]}"
    client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"], request_timeout: 600)
    response = client.audio.transcribe(
      parameters: {
        model: "whisper-1",
        file: File.open(mp3_path, "rb"),
        prompt: CHANNELING_PROMPT
      }
    )
    response["text"]
  end
end

def posts_with_transcribe_true
  Dir["#{POSTS_DIR}/*.md"].sort.select do |path|
    content = File.read(path)
    next false unless content =~ /\A---\s*\n(.*?)---\s*\n(.*)/m
    fm = Regexp.last_match(1)
    fm.match?(/^transcribe:\s*true/mi)
  end
end

def audio_url_from_post(content)
  return nil unless content =~ /\A---\s*\n(.*?)---/m
  fm = Regexp.last_match(1)
  return nil unless fm =~ /^audio:\s*["']?([^"'\s]+)["']?\s*$/m
  Regexp.last_match(1).strip
end

def download_audio(url, local_path)
  # Use aws s3 cp for S3 URLs (works with private buckets); curl for other HTTPS
  if url =~ %r{^https://([^.]+)\.s3\.([^.]+)\.amazonaws\.com/(.+)$}
    bucket = Regexp.last_match(1)
    region = Regexp.last_match(2)
    key = Regexp.last_match(3)
    s3_uri = "s3://#{bucket}/#{key}"
    region_arg = (region == "us-east-1") ? [] : ["--region", region]
    return system("aws", "s3", "cp", s3_uri, local_path, *region_arg)
  end
  system("curl", "-sL", url, "-o", local_path)
end

def update_post(post_path, transcript)
  content = File.read(post_path)
  return false unless content =~ /\A---\n(.*?)---\n(.*)/m

  fm = Regexp.last_match(1)
  body = Regexp.last_match(2)

  # Remove transcribe: true line
  new_fm = fm.sub(/^transcribe:\s*true\s*\n?/mi, "")
  new_fm = new_fm.rstrip

  new_content = "---\n#{new_fm}\n---\n\n#{transcript}\n"
  File.write(post_path, new_content)
  true
end

def main
  dry_run = ARGV.delete("--dry-run")

  abort "Set OPENAI_API_KEY" if ENV["OPENAI_API_KEY"].to_s.strip.empty?

  posts = posts_with_transcribe_true
  if posts.empty?
    puts "No posts with transcribe: true."
    return
  end

  puts "Found #{posts.size} post(s) with transcribe: true"
  puts "(dry-run)" if dry_run

  updated = 0
  posts.each do |post_path|
    content = File.read(post_path)
    audio_url = audio_url_from_post(content)
    unless audio_url
      puts "  #{File.basename(post_path)}: SKIP (no audio URL)"
      next
    end

    mp3_basename = File.basename(audio_url.split("?").first)
    mp3_basename = "audio.mp3" unless mp3_basename.end_with?(".mp3")
    local_mp3 = File.join(Dir.tmpdir, mp3_basename)

    print "  #{File.basename(post_path)}: fetch #{audio_url} ... "
    unless download_audio(audio_url, local_mp3)
      puts "SKIP (download failed)"
      next
    end
    puts "OK"

    next if dry_run

    print "         transcribe ... "
    transcript = Transcriber.call(local_mp3)
    puts "OK (#{transcript.length} chars)"
    File.unlink(local_mp3) if File.exist?(local_mp3)

    if update_post(post_path, transcript)
      puts "         updated #{post_path}"
      updated += 1
    else
      puts "         FAILED to update"
    end
  end

  puts "\nUpdated #{updated} post(s)" unless dry_run
end

main
