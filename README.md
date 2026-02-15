# HARC Jekyll site

Jekyll site for High Altitude Receiving Center. Theme converted from the WordPress “HARC Amalie Lite Child” theme.

## Structure

- **`_config.yml`** – Site title, pagination (15 posts per page), optional logo path.
- **`_layouts/`** – `default`, `post`, `archive`.
- **`_includes/`** – Header, footer, post subtitle, post excerpt.
- **`index.html`** – Home page (paginated post list).
- **`assets/css/style.css`** – Theme styles.

## Post front matter

| Field        | Description                          |
|-------------|--------------------------------------|
| `title`     | Post title                           |
| `date`      | Session/post date                    |
| `circle`    | Circle name                          |
| `event`     | Event name                           |
| `session`   | Session number                       |
| `categories`| e.g. `Transcripts`, `Training Session` |
| `tags`      | Optional tags                        |
| `audio`     | URL to audio file (S3 URL or path like `/assets/audio/xxx.mp3`). When set, an HTML5 audio player is shown on the post page. |

Posts in the **Training Session** category get the training label and caveat on the single post view.

## Logo

In `_config.yml`: `logo: "/assets/logo.png"` (or leave empty to hide).

## Migrating from WordPress (har.center)

1. **Export** from WordPress: **Tools → Export** → choose **All content** → **Download Export File** (saves an XML file).
2. **Run the migration script:**
   ```bash
   bundle install
   ruby scripts/wxr_to_jekyll.rb ~/Downloads/harc_wp.xml --dry-run   # Preview
   ruby scripts/wxr_to_jekyll.rb ~/Downloads/harc_wp.xml            # Write to _posts/
   ```
3. The script reads custom fields and categories from the WXR, maps circle/event/session into filenames (`YYYY-MM-DD_circle_event_session.md`), and extracts Introduction and Group question from the content into front matter.

If har.center uses different custom field names or category structures, the script may need tweaks. See `scripts/wxr_to_jekyll.rb` for the mapping logic.

4. **Add audio to posts** (optional): If your WordPress export includes audio (enclosure elements or `media` postmeta), run:
   ```bash
   ruby scripts/add_audio_from_wxr.rb ~/Downloads/harc_wp.xml --dry-run   # Preview
   ruby scripts/add_audio_from_wxr.rb ~/Downloads/harc_wp.xml              # Download to assets/audio, add audio: to front matter
   ```
   If the WXR contains audio URLs from an old domain (e.g. `harc.otherselvesworking.group`), rewrite them before downloading:
   ```bash
   ruby scripts/add_audio_from_wxr.rb ~/Downloads/harc_wp.xml --replace-url harc.otherselvesworking.group=har.center
   ```
   The script extracts audio URLs from the WXR, downloads them to `assets/audio/`, and adds an `audio` field to each matching post. Posts with `audio` set will display an HTML5 audio player.

## Deploy (S3 + GitHub)

Audio files are stored in S3 to keep the repo small. The deploy script uploads MP3s, updates frontmatter with S3 URLs, and pushes to `origin main`.

**Prerequisites:** AWS CLI configured (`aws configure`) with write access to your S3 bucket.

```bash
# Create an S3 bucket and set public read access for the audio prefix if needed
export HARC_S3_BUCKET=your-bucket-name
# Optional: HARC_S3_PREFIX=audio (default), HARC_S3_REGION=us-east-1

ruby scripts/deploy.rb              # Upload, update frontmatter, commit & push
ruby scripts/deploy.rb --dry-run    # Preview without committing
ruby scripts/deploy.rb --no-push    # Upload and commit, but don't push
```

MP3s in `assets/audio/` are gitignored. Keep them locally for deploys; the script uploads them to S3 and rewrites `audio:` in post frontmatter to full S3 URLs.

## Run locally

```bash
bundle install
bundle exec jekyll serve
```

Open http://localhost:4000.
