#!/usr/bin/env ruby
# frozen_string_literal: true

# Find orphan MP3s on S3 (no matching post). For each: download, transcribe, create post.
# Used by the transcribe-missing-audio GitHub Action.
#
# Large files (>= 25 MB, OpenAI's limit) are compressed to a temp copy for
# transcription.
#
# Usage:
#   OPENAI_API_KEY=xxx AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=xxx ruby scripts/transcribe_missing_audio.rb
#   OPENAI_API_KEY=xxx ruby scripts/transcribe_missing_audio.rb --dry-run
#
# Env:
#   OPENAI_API_KEY          (required)
#   AWS_ACCESS_KEY_ID       (required for S3)
#   AWS_SECRET_ACCESS_KEY   (required for S3)
#   HARC_S3_BUCKET          (default: harc-assets)
#   HARC_S3_PREFIX          (default: audio)
#
# Deps:
#   aws CLI, ffmpeg, ffprobe

require "openai"
require "pathname"
require "tempfile"

POSTS_DIR = "_posts"
S3_BUCKET = ENV.fetch("HARC_S3_BUCKET", "harc-assets")
S3_PREFIX = ENV.fetch("HARC_S3_PREFIX", "audio")

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
    client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"], timeout: 600)
    file = Pathname(mp3_path).expand_path
    # Use FilePart so API gets explicit filename and content-type (avoids "Invalid file format" errors)
    file_part = OpenAI::FilePart.new(file, content_type: "audio/mpeg")
    response = client.audio.transcriptions.create(
      file: file_part,
      model: "whisper-1",
      prompt: CHANNELING_PROMPT
    )
    response.text
  end
end

MAX_FILE_SIZE_MB = 25

def with_audio_for_transcription(mp3_path)
  size_mb = File.size(mp3_path) / (1024.0 * 1024)

  if size_mb < MAX_FILE_SIZE_MB
    yield mp3_path
    return
  end

  duration = `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "#{mp3_path}" 2>/dev/null`.to_f
  duration = 3600.0 if duration <= 0

  max_bits = MAX_FILE_SIZE_MB * 1024 * 1024 * 8 * 0.9
  bitrate_bps = (max_bits / duration).to_i
  bitrate_k = [[32, bitrate_bps / 1000].max, 128].min

  Tempfile.create(["transcribe_", ".mp3"]) do |temp|
    temp.close
    temp_path = temp.path
    success = system("ffmpeg", "-y", "-i", mp3_path, "-ac", "1", "-b:a", "#{bitrate_k}k",
      temp_path, out: File::NULL, err: File::NULL)
    abort "ffmpeg failed to compress audio (is ffmpeg installed?)" unless success
    yield temp_path
  end
end

def s3_mp3_slugs
  output = `aws s3 ls "s3://#{S3_BUCKET}/#{S3_PREFIX}/" 2>/dev/null` or return []
  output.each_line.select { |line| line.strip.end_with?(".mp3") }
    .map { |line| line.split.last.sub(/\.mp3\z/, "") }
    .sort
end

def existing_post_slugs
  Dir.glob("#{POSTS_DIR}/**/*.md").map { |p| File.basename(p, ".md") }.uniq
end

def orphan_mp3s
  s3_slugs = s3_mp3_slugs
  return [] if s3_slugs.empty?
  posts = existing_post_slugs
  s3_slugs.reject { |slug| posts.include?(slug) }
end

def download_from_s3(slug, dest_path)
  s3_uri = "s3://#{S3_BUCKET}/#{S3_PREFIX}/#{slug}.mp3"
  system("aws", "s3", "cp", s3_uri, dest_path, out: File::NULL, err: File::NULL)
end

def create_post(post_filename, transcript)
  content = <<~MD
    ---
    title: TBD
    group_question: TBD
    introduction: TBD
    categories:
    - TBD
    ---

    #{transcript}
  MD
  File.write(File.join(POSTS_DIR, post_filename), content)
end

def main
  dry_run = ARGV.delete("--dry-run")

  abort "Set OPENAI_API_KEY" if ENV["OPENAI_API_KEY"].to_s.strip.empty?
  abort "Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY for S3" if
    ENV["AWS_ACCESS_KEY_ID"].to_s.strip.empty? || ENV["AWS_SECRET_ACCESS_KEY"].to_s.strip.empty?

  orphans = orphan_mp3s
  if orphans.empty?
    puts "No orphan MP3s on S3."
    return
  end

  puts "Found #{orphans.size} orphan MP3(s) on S3"
  puts "(dry-run)" if dry_run

  created = 0
  orphans.each do |mp3_basename|
    post_filename = "#{mp3_basename}.md"

    print "  #{mp3_basename}.mp3 ... "
    if dry_run
      puts "OK (dry-run)"
      next
    end

    Tempfile.create(["transcribe_dl_", ".mp3"]) do |temp|
      temp.close
      unless download_from_s3(mp3_basename, temp.path)
        puts "FAILED (download from S3)"
        next
      end

      print "transcribe ... "
      transcript = nil
      with_audio_for_transcription(temp.path) { |audio_path| transcript = Transcriber.call(audio_path) }
      puts "OK (#{transcript.length} chars)"

      create_post(post_filename, transcript)
      puts "         created #{POSTS_DIR}/#{post_filename}"
      created += 1
    end
  end

  puts "\nCreated #{created} post(s)" unless dry_run
end

main
