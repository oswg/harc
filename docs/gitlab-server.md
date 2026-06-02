# Controlling GitLab after bootstrap

This guide describes how to administer a GitLab server installed with [`scripts/setup_gitlab_server.sh`](../scripts/setup_gitlab_server.sh).

With this setup you control GitLab in three layers: the **web UI** (day-to-day), **SSH as `deploy`** (server admin), and **`gitlab-ctl`** (GitLab service itself).

## 1. Web UI (most control)

After DNS points at the box and the install finishes:

1. Open `GITLAB_EXTERNAL_URL` (e.g. `https://git.example.com`).
2. Sign in as **`root`**.
   - If you set `GITLAB_ROOT_PASSWORD`, use that.
   - Otherwise read the one-time password on the server:

     ```bash
     ssh -p 24197 deploy@your-server
     sudo cat /etc/gitlab/initial_root_password
     ```

3. From there you manage almost everything:
   - **Projects, groups, users, permissions**
   - **CI/CD** (pipelines, variables, runners)
   - **Admin area** (wrench icon) → Settings, integrations, Pages, etc.

Create a personal admin account, use it daily, and disable or stop using `root` once you’re set up.

## 2. SSH to the server (`deploy` user)

Admin access to the **host** (not GitLab’s git user):

```bash
ssh -p 24197 deploy@your-server
```

- Key-only auth (the key you passed as `ADMIN_SSH_PUBLIC_KEY`).
- Port **24197** (not 22).
- `deploy` has **sudo** for system tasks.

From there you run GitLab omnibus commands with sudo:

```bash
sudo gitlab-ctl status
sudo gitlab-ctl restart
sudo gitlab-ctl tail          # logs
sudo gitlab-ctl reconfigure   # after editing /etc/gitlab/gitlab.rb
```

## 3. Git over SSH (repos)

Clone/push uses the **`git`** user on the same port:

```bash
git clone ssh://git@your-server:24197/group/project.git
```

Or with `~/.ssh/config`:

```
Host gitlab
  HostName your-server
  Port 24197
  User git
```

GitLab manages `git`’s keys via the web UI (user SSH keys / deploy keys), not by editing `authorized_keys` by hand.

## 4. Changing GitLab configuration

Persistent config lives in **`/etc/gitlab/gitlab.rb`**. The setup script maintains a marked block (`gitlab-setup-script BEGIN/END`); you can edit that file for other settings too, then:

```bash
sudo gitlab-ctl reconfigure
```

Examples: change Pages URL, enable/disable features, tune resources. If you used `GITLAB_ENABLE_LETSENCRYPT=1`, TLS is handled there as well.

## 5. CI runners

The bootstrap script installs **gitlab-runner** but does **not** register it. After logging into the UI:

1. **Admin → CI/CD → Runners** → create/register a runner and copy the token.
2. On the server:

   ```bash
   sudo gitlab-runner register \
     --url https://git.example.com \
     --token <token> \
     --executor docker
   ```

Then control runners from the UI or with `sudo gitlab-runner list`, `sudo gitlab-runner restart`, etc.

## Quick reference

| What you want | How |
|---------------|-----|
| Manage projects, users, CI | Web UI at `GITLAB_EXTERNAL_URL` |
| Server + GitLab service ops | `ssh -p 24197 deploy@host` → `sudo gitlab-ctl …` |
| Git clone/push | `git@host` on port **24197** |
| Firewall / SSH policy | UFW + `/etc/ssh/sshd_config.d/99-gitlab-setup.conf` (via sudo on host) |
| Backups | Not automated by the script — configure in **Admin → Settings → Backups** or `gitlab-backup` |

If you set **`ADMIN_IP`**, SSH (and thus host admin) only works from that CIDR; the web UI is still reachable on 443 from anywhere unless you restrict it further.

## Related

- Bootstrap script and environment variables: [`scripts/setup_gitlab_server.sh`](../scripts/setup_gitlab_server.sh)
- Example invocation: [README § GitLab server bootstrap](../README.md#gitlab-server-bootstrap)
