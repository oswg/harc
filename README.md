# High Altitude Receiving Center
## An archive of contact with the Confederation

This repo constitutes a Jekyll static site generator for the High Altitude Receiving Center (HARC) website. Theme converted from the WordPress "Amalie Lite" theme. Includes github workflows that automatically transcribe mp3s.

## Getting started

The best way to start is to install git on your machine, designate a directory where this code lives, and clone the repository (`git clone https://github.com/oswg/harc.git` or use the Github CLI). Go into that directory, install Ruby and Bundler, and then `bundle install` and `bundle exec jekyll serve`. If everything goes right, you be able to navigate in your browser to [http://localhost:4000](http://localhost:4000) and see a usuable HARC site, right on your machine. Any changes you make to the content or code will be reflected on that site, so it's a good way to double check your submissions.

### One-time migration (if moving from tracked MP3s)

If the repo previously had MP3s in git/LFS, remove them from tracking:

```bash
git rm -r --cached assets/audio/
git commit -m "chore: move audio to S3, stop tracking assets/audio"
```

### Audio setup (required for contributors adding MP3s)

MP3s are stored on S3, not in the repo. Before adding new audio:

1. Install the pre-push hook: `./scripts/install_audio_sync_hook`
2. Set AWS credentials: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (obtain from repo maintainer)
3. Add MP3s to `assets/audio/` locally (this directory is gitignored)

On each `git push`, the hook syncs local `assets/audio/` to S3 and updates the audio manifest. The transcribe workflow then finds orphan MP3s on S3 and creates posts.

### Post and audio filename structure

In order for the site to work with new session posts, they have to be named in a certain pattern, given an extension (if you use Markdown, `.md` is the extension), and placed in `_posts/`. Notice that underscores separate descriptive "slugs" or short indicators, which must be in this order:

`2025-04-05_circle-a_event-x_001`

In the above example here `2025-04-05` is the date (April 5, 2025), `circle-a` would refer to circle it maps to in `category_descriptions.yml`, same with `event-x` and `001` is the session number. This base filename would have a `.md` extension in `_posts` and a `.mp3` extension under `assets/audio`. 

### Post front matter

| Field        | Description                          |
|-------------|--------------------------------------|
| `title`     | Post title                           |
| `date`      | Session/post date                    |
| `circle`    | Circle name                          |
| `event`     | Event name                           |
| `session`   | Session number                       |
| `categories`| e.g. `Transcripts`, `Training Session` |
| `tags`      | Optional tags                        |

Posts in the **Training Session** category get the training label and a caveat added once rendered. They are excluded from the index feed, but available by going to any category page.

## More on how to contribute

Direct commits to `main` are disabled; that's the branch we use for publishing the site. All changes must go through a pull request, which requires you to:

1. Create your own branch for the new content
2. Add the MP3 to `assets/audio/` locally (gitignored; synced to S3 by pre-push hook)
3. Run `./scripts/install_audio_sync_hook` if you haven't, set AWS credentials, then push: `git push origin <branch name>`
4. Give it about 5 minutes or so, then `git pull origin main` should pull down a provisional post matching the filename structure of your mp3 but with the `.md` extension under `_posts/`.
5. Flesh out the front matter data at the top of the post and submit a pull request. Other members of HARC will review and when approved, your post will be merged into `main` and published.

You will need to talk to `jeremy6d` if you want to contribute.

### Adding a new session

1. Create a branch: `git checkout -b add-session-YYYY-MM-DD_event_NNN`
2. Add the MP3 to `assets/audio/` (see filename structure above). Ensure the pre-push hook is installed and AWS credentials are set.
3. Commit (manifest only, if changed) and push the branch
4. After about five minutes or so, run `git pull` to view the transcribed post under `_posts/`.
5. Edit the post, fleshing out the front matter data at the top of the post, checking that the transcription is accurate, adding instrument change notes, etc.
6. Commit and push to your branch, and then submit a pull request on the branch.
7. Other members of HARC will review and when approved, your post will be merged into `main` and published.
8. Checkout `main` again and clean up the old branch no longer needed.

### More details about the transcription workflow

MP3s are stored on S3 (synced from local `assets/audio/` by the pre-push hook) and served from S3. The transcribe workflow runs when changes are pushed to a branch _other than_ `main`. It finds orphan MP3s on S3 (no matching post), downloads each, transcribes, and creates a new post with dummy frontmatter and the transcript in the body. **Make sure you `git pull` after you give it a chance to create the stub post.** You then need to edit the transcript, adding introduction, group question, instrument change notes, footnotes, paragraphs, and correcting any Whisper errors.

## Usage rights and copyright

This entire repository and any forks are copyrighted work. You may share freely as long as you attribute the work to HARC or the instruments involved. Feel free to fork, but keep in mind that it won't be published until it's approved by HARC staff.

Reach out if you need any assistance, if you have a circle practicing Carla Rueckert's protocols and want to get involved, or if you have a background in this tradition and would like to review new submissions.

**Go forth, therefore, rejoicing merrily in the power and the peace of the One Infinite Creator.** 
