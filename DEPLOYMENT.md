# Deploying Spidder to a VPS

Postgres, Redis and nginx run **on the host**, managed by systemd. Everything
else — the four app services and the Piston sandbox — runs in Docker, owned by
an unprivileged `deploy` user. Nothing here needs root after setup.

Two things shape the rest of this guide. Containers cannot reach a host service
by `localhost`, so Postgres and Redis must listen on the Docker bridge and the
firewall must then keep that bridge off the public internet. And the app
containers publish only to `127.0.0.1`, so nginx is the single way in.

```
                        ┌──────────────── VPS ──────────────────┐
                        │                                       │
  browser ──── :443 ──▶ │  nginx (host, systemd)                │
                        │    │                                  │
     spidder.example.com    ─┼─▶ 127.0.0.1:3001  web            │
                        │    │                                  │
 api.spidder.example.com    ─┼─▶ 127.0.0.1:4001  http-api       │
            /ws         │    └─▶ 127.0.0.1:4002  ws-server      │
                        │              │                        │
                        │   ┌──────────┴────────────┐           │
                        │   ▼                       ▼           │
                        │ postgres :5432      redis :6379       │
                        │ (host, systemd)     (host, systemd)   │
                        │   ▲                       ▲           │
                        │   └─ host.docker.internal ┘           │
                        │       (docker bridge, 172.17.0.1)     │
                        │                                       │
                        │  judge-worker ──▶ piston (container)  │
                        │                                       │
                        │  ── docker compose, run as `deploy` ──│
                        └───────────────────────────────────────┘
```

---

## 1. Create the deploy user

Everything below runs as a dedicated `deploy` user, never as root. Two reasons
that matter in practice: a mistake in a deploy script cannot touch the rest of
the system, and the SSH key CI holds is scoped to one account you can revoke
without locking yourself out.

SSH in as root **one last time**:

```bash
adduser --disabled-password --gecos "" deploy
```

`--disabled-password` means the account has no password to guess. You will
reach it by key only, which is what you want for an account CI can drive.

### Give it sudo, but keep it honest

```bash
usermod -aG sudo deploy
```

The deploy user needs sudo for the *setup* in sections 2–5 — installing
packages, editing Postgres config, managing nginx. It does **not** need sudo
for deploys: once Docker is set up, `docker compose` runs as the user itself.
If you want to lock it down further after setup, remove it from `sudo` and the
CI deploy will still work.

### Let it use Docker without sudo

```bash
usermod -aG docker deploy
```

This is what makes the CI deploy possible: the workflow SSHes in and runs
`docker compose` directly, with no password prompt to get stuck on.

> **Be clear-eyed about this.** Membership of the `docker` group is effectively
> root: anyone in it can start a container that mounts `/` and edit anything on
> the host. It is the standard way to run deploys and it is what the CI
> workflow needs, but it means the `deploy` SSH key is a root-equivalent
> credential. Treat it that way — dedicated key, no passphrase reuse, revoke it
> if a laptop goes missing.

### Set up SSH access

On **your laptop**, generate a key used for nothing else:

```bash
ssh-keygen -t ed25519 -C "spidder-deploy" -f ~/.ssh/spidder_deploy -N ""
ssh-copy-id -i ~/.ssh/spidder_deploy.pub deploy@your.vps.ip
```

Confirm it works **before** you lock root out:

```bash
ssh -i ~/.ssh/spidder_deploy deploy@your.vps.ip 'id && sudo -n true && echo "sudo ok"'
```

You should see `deploy` in the groups, including `docker`.

### Close the root door

Only once the line above succeeds. In `/etc/ssh/sshd_config`:

```conf
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

```bash
sudo sshd -t          # syntax check FIRST — a typo here locks you out
sudo systemctl reload ssh
```

Keep your existing session open while you test a *new* one in another
terminal. If the new session fails you still have the old one to fix it with.

---

## 2. Host prerequisites

Ubuntu 22.04+ or Debian 12+, 2 vCPU / 4 GB RAM minimum. The Next.js build does
not run here — CI builds the images — but Piston plus four Node processes want
headroom.

As `deploy`:

```bash
sudo apt update && sudo apt install -y \
  postgresql postgresql-contrib redis-server nginx git ufw \
  certbot python3-certbot-nginx

# Docker engine + compose plugin
curl -fsSL https://get.docker.com | sudo sh
```

You added `deploy` to the `docker` group in section 1, but **group membership
only applies to new sessions**. Log out and back in, then confirm:

```bash
docker ps        # must work with no sudo
```

If that still says "permission denied", the session is stale — reconnect.

---

## 3. Postgres

Create the database and a role that is **not** the superuser:

```bash
sudo -u postgres psql <<'SQL'
CREATE ROLE spidder WITH LOGIN PASSWORD 'use-a-long-random-password';
CREATE DATABASE spidder OWNER spidder;
SQL
```

Now make it reachable from the containers. Find the bridge address first —
`172.17.0.1` is the common default but not guaranteed:

```bash
ip -4 addr show docker0 | awk '/inet /{print $2}'   # e.g. 172.17.0.1/16
```

Find your config directory (the version number varies):

```bash
sudo -u postgres psql -c 'SHOW config_file;'
```

In `postgresql.conf`:

```conf
listen_addresses = 'localhost,172.17.0.1'
```

In `pg_hba.conf` — the whole private range, because a container's own address
is assigned per-network and will not be the gateway:

```conf
host    spidder    spidder    172.16.0.0/12    scram-sha-256
```

```bash
sudo systemctl restart postgresql
```

Verify from inside a container, which is the only test that proves the path:

```bash
docker run --rm --add-host=host.docker.internal:host-gateway alpine:3.20 \
  sh -c 'nc -z -w3 host.docker.internal 5432 && echo CONNECTED || echo REFUSED'
```

`REFUSED` means Postgres is still loopback-only — re-check `listen_addresses`.

---

## 4. Redis

Find the config with `sudo systemctl cat redis-server | grep ExecStart`, then
in `/etc/redis/redis.conf`:

```conf
bind 127.0.0.1 172.17.0.1
requirepass use-another-long-random-password
protected-mode yes
appendonly yes
```

```bash
sudo systemctl restart redis-server
```

> **Set the password.** Leaving Redis open on the bridge means anything that
> gets a shell in any container — including the sandbox that runs submitted
> code — has full read/write access to your job queue.

---

## 5. Firewall

The bridge is now listening. Close the public door before going further:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
```

Ports 5432 and 6379 are deliberately absent, and so are 3001/4001/4002. The
containers publish those to `127.0.0.1` only and nginx reaches them there;
nothing from outside should.

Verify from your laptop — all of these should hang and time out:

```bash
nc -zv your.vps.ip 5432
nc -zv your.vps.ip 6379
nc -zv your.vps.ip 4001
```

---

## 6. The application

As `deploy`, in a directory the user owns:

Clone into the deploy user's own home directory — no `sudo`, no `chown`, since
the user already owns it:

```bash
cd ~
git clone https://github.com/TheCodeHeist-Coder/Spidder.git spidder
cd ~/spidder

cp .env.prod.example .env
chmod 600 .env
$EDITOR .env          # fill in every CHANGE_ME
```

`chmod 600` matters: that file holds your database password and JWT secret.
Tighten the home directory too — some distros create it `755`, which lets any
other account on the box read it:

```bash
chmod 750 ~
```

`/opt/spidder` or `/srv/spidder` work equally well if you prefer a conventional
location; they just need `sudo mkdir` and `sudo chown deploy:deploy` first.
Whatever you choose, `VPS_APP_DIR` must match it.

Generate the secrets rather than inventing them:

```bash
openssl rand -hex 32   # JWT_SECRET
openssl rand -hex 24   # database / redis passwords
```

Then bring it up:

```bash
docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml ps
```

`db-init` applies the schema and seeds the problem bank, then exits 0. The app
services wait for it, so the first request never hits an empty database.

---

## 7. nginx and TLS

The containers publish to `127.0.0.1` only, so nginx is not optional — it is
the only way in.

Two server blocks: one for the site, one for the API. They are separate
hostnames because the browser bundle is compiled with absolute URLs
(`NEXT_PUBLIC_API_URL`), and keeping the API on its own name means you can move
or scale it later without rebuilding the frontend.

### DNS first

Point both names at the VPS before requesting certificates — certbot proves
control by answering an HTTP challenge on them:

```
A    spidder.example.com       -> your.vps.ip
A    api.spidder.example.com   -> your.vps.ip
```

Check it has propagated: `dig +short spidder.example.com`.

### The site block

`/etc/nginx/sites-available/spidder`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name spidder.example.com;

    # certbot fills in the TLS config and the redirect below.
    location / {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host  $host;

        # Next.js streams server components; buffering them defeats the point
        # and makes the first paint wait for the whole response.
        proxy_buffering off;
    }

    # Next's immutable build assets. Hashed filenames, so a long cache is safe
    # and saves the Node process from serving them at all on repeat visits.
    location /_next/static/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_cache_valid 200 60m;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    client_max_body_size 2m;
}
```

### The API block

This one carries the WebSocket, and the upgrade headers are the part people
miss — without them battles never start while everything else looks fine.

`/etc/nginx/sites-available/spidder-api`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name api.spidder.example.com;

    # --- realtime: ws-server -------------------------------------------------
    # Must come before the catch-all `location /`, or the API block below
    # swallows it and the upgrade never happens.
    location /ws {
        proxy_pass http://127.0.0.1:4002;
        proxy_http_version 1.1;

        # The three lines that make a WebSocket work. $connection_upgrade is
        # defined in the map block below — using a literal "upgrade" here
        # breaks ordinary requests that share the connection.
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host       $host;

        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # A battle outlives nginx's 60s default, and the socket is idle
        # whenever nobody is typing. Without this the connection is cut
        # mid-match and the client reconnects into a battle already moving.
        proxy_read_timeout  3600s;
        proxy_send_timeout  3600s;

        # Realtime frames must not be held back waiting for a buffer to fill.
        proxy_buffering off;
    }

    # --- ws-server's health probe -------------------------------------------
    # Useful for external uptime monitoring. Cheap, and leaks nothing.
    location = /ws-health {
        proxy_pass http://127.0.0.1:4002/health;
        proxy_set_header Host $host;
        access_log off;
    }

    # --- BLOCKED: ws-server's internal stats ---------------------------------
    # /internal/* is server-to-server only and has NO authentication — see
    # apps/ws-server/src/transport/httpApp.ts. http-api reaches it over the
    # Docker network; it must never be routable from outside. This block is
    # belt-and-braces (the proxy_pass above targets 4002 only under /ws), but
    # an explicit deny survives someone later adding a broader location.
    location /internal/ {
        return 404;
    }

    # --- everything else: http-api -------------------------------------------
    location / {
        proxy_pass http://127.0.0.1:4001;
        proxy_http_version 1.1;

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_read_timeout 60s;
    }

    # Code submissions are the largest thing a client sends, and they are
    # text. 2 MB is generous; the app caps source at 100 KB anyway.
    client_max_body_size 2m;
}
```

### The upgrade map

`$connection_upgrade` has to be defined at the `http` level, not inside a
server block. Create `/etc/nginx/conf.d/upgrade.conf`:

```nginx
# Maps the Upgrade request header to the right Connection response header.
#
# A plain `Connection: upgrade` on every request breaks keep-alive for normal
# HTTP; this sends "upgrade" only when the client actually asked for one, and
# "close" otherwise.
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
```

### Enable and test

```bash
sudo ln -s /etc/nginx/sites-available/spidder      /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/spidder-api  /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

sudo nginx -t          # ALWAYS before reload
sudo systemctl reload nginx
```

### Certificates

```bash
sudo certbot --nginx \
  -d spidder.example.com \
  -d api.spidder.example.com \
  --agree-tos -m you@example.com --redirect
```

`--redirect` adds the HTTP→HTTPS redirect. certbot rewrites both server blocks
in place, adding `listen 443 ssl`, the certificate paths, and a port-80 block
that redirects. Renewal is installed as a systemd timer; check it with:

```bash
systemctl list-timers | grep certbot
sudo certbot renew --dry-run
```

### Verify the whole path

```bash
curl -I  https://spidder.example.com
curl -s  https://api.spidder.example.com/health          # {"ok":true}
curl -s  https://api.spidder.example.com/ws-health       # {"ok":true}
curl -s -o /dev/null -w '%{http_code}\n' \
     https://api.spidder.example.com/internal/stats      # 404 — must NOT be 200

# The WebSocket upgrade. 101 means the handshake worked.
curl -i -N \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Key: $(openssl rand -base64 16)" \
  -H "Sec-WebSocket-Version: 13" \
  https://api.spidder.example.com/ws 2>&1 | head -1
```

A `200` on `/internal/stats` means the deny block is missing or ordered wrong —
fix it before going live.

### What about the admin dashboard?

`apps/admin` has **no `Dockerfile.prod`** and appears in no compose file, so
there is nothing to proxy to yet — that is why no third server block is given
here. The admin API routes live inside `http-api` and are already reachable
through `api.spidder.example.com`; only the separate Next.js UI is missing.

When it is containerised, it needs its own hostname and a block identical to
the site one, pointing at its port — and it should sit behind something more
than a login form: an IP allowlist (`allow`/`deny`) or basic auth at the nginx
layer, because it is the one surface where a stolen session is worth the most.

### Point the app at these names

Two places, and they must agree:

1. **Repository secrets** — `NEXT_PUBLIC_API_URL=https://api.spidder.example.com`
   and `NEXT_PUBLIC_WS_URL=wss://api.spidder.example.com/ws`. Note `wss://`,
   not `ws://`: a plain-ws connection from an https page is blocked by the
   browser as mixed content.
2. **The server's `.env`** — `CORS_ORIGINS=https://spidder.example.com`. This
   is the *site* origin, not the API's; it is the origin the browser sends.

The `NEXT_PUBLIC_*` pair is compiled into the browser bundle at image build
time, so changing them means re-running the deploy workflow. Changing
`CORS_ORIGINS` only needs a restart.

---

## 8. CI/CD

### What runs when

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | every push, every PR | lint, typecheck, tests, full build |
| `deploy.yml` | push to `main`, or manual | re-verify → build 5 images → push to Docker Hub → roll out |

Images are built on the runner, never on the VPS. Building a Next.js app on a
small droplet competes with the running site for memory and can OOM halfway,
taking production down to ship a change. A runner builds it, the server pulls
the result.

Every deploy is tagged with its commit SHA, so a rollback is re-running the
workflow against an older commit rather than reverting and rebuilding.

### Repository secrets

`Settings → Secrets and variables → Actions`:

| Secret | Example | Notes |
|---|---|---|
| `DOCKERHUB_USERNAME` | `codeheist` | your Docker Hub account, lowercase |
| `DOCKERHUB_TOKEN` | `dckr_pat_…` | an **access token**, not your password |
| `VPS_HOST` | `203.0.113.10` | hostname or IP |
| `VPS_USER` | `deploy` | must be in the `docker` group |
| `VPS_SSH_KEY` | `-----BEGIN OPENSSH…` | the **private** key, whole file |
| `VPS_APP_DIR` | `/home/deploy/spidder` | absolute path, not `~` |
| `NEXT_PUBLIC_API_URL` | `https://api.spidder.example.com` | baked into the browser bundle |
| `NEXT_PUBLIC_WS_URL` | `wss://api.spidder.example.com/ws` | note `wss://`, not `ws://` |
| `VPS_SSH_PORT` | `22` | optional |

### Docker Hub

Create the access token at **hub.docker.com → Account Settings → Personal
access tokens**, scope **Read & Write**. Use a token rather than your password:
a token can be revoked on its own, and it cannot be used to sign in to the
account itself.

The workflow pushes five images:

```
<username>/spidder-http-api
<username>/spidder-ws-server
<username>/spidder-judge-worker
<username>/spidder-web
<username>/spidder-db-init
```

They are created on first push. **The free tier includes one private
repository**, so five private images needs a paid plan — otherwise create them
as public. They hold only compiled application code; every credential is
injected at runtime from the server's `.env`, so nothing secret ships inside
them. The one thing compiled *in* is `NEXT_PUBLIC_*` in the web image, and
those are public URLs visible in any visitor's devtools regardless.

The compose file already defaults to `codeheist`, so a hand-run
`docker compose` on the VPS resolves the same images the workflow pushes. If
you publish under a different Docker Hub account, set `REGISTRY` in the
server's `.env` to match `DOCKERHUB_USERNAME` — otherwise the server keeps
pulling the original account's images while CI pushes to yours, and the deploy
appears to succeed while changing nothing.

### The deploy key

Generate a keypair used by nothing else:

```bash
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/spidder_deploy -N ""
ssh-copy-id -i ~/.ssh/spidder_deploy.pub deploy@your.vps.ip
cat ~/.ssh/spidder_deploy          # paste ALL of this into VPS_SSH_KEY
```

### First run

The workflow logs the server in to Docker Hub before pulling, even when the
images are public. That is on purpose: anonymous pulls are rate-limited per IP
address, and a VPS that shares an address range with other pullers can hit the
ceiling partway through a deploy. The failure is a `429 Too Many Requests` on
`docker compose pull`, which reads like an outage rather than a quota. An
authenticated pull uses the account's own, much higher limit.

A first deploy failing with `pull access denied` or `repository does not exist`
means the namespace is wrong — check `DOCKERHUB_USERNAME` is your Hub account
(not your GitHub org) and is lowercase.

---

## Operations

Everything here runs as `deploy`, with no sudo — that is the point of section 1.

```bash
cd ~/spidder

# A short alias saves repeating the -f on every command.
alias dc='docker compose -f docker-compose.prod.yml'

dc ps                       # what is running, and is it healthy
dc logs -f --tail=100       # everything
dc logs -f http-api         # one service
dc restart http-api
dc pull && dc up -d         # roll to the latest images by hand
```

nginx, Postgres and Redis are host services, so they use systemd and do need
sudo:

```bash
sudo systemctl status nginx postgresql redis-server
sudo nginx -t && sudo systemctl reload nginx    # ALWAYS test before reload
sudo tail -f /var/log/nginx/error.log
```

### Backups

The database is on the host, so it is not in any Docker volume:

```bash
# /etc/cron.daily/spidder-backup
sudo -u postgres pg_dump spidder | gzip > /var/backups/spidder-$(date +%F).sql.gz
find /var/backups -name 'spidder-*.sql.gz' -mtime +14 -delete
```

Restore:

```bash
gunzip -c /var/backups/spidder-2026-09-13.sql.gz | sudo -u postgres psql spidder
```

### Rollback

The fastest route is the Actions tab: re-run **Deploy** on the last good
commit. To pin by hand on the server instead — `IMAGE_TAG` is the only knob,
since the Docker Hub account is written literally in the compose file:

```bash
cd ~/spidder
IMAGE_TAG=<good-sha> docker compose -f docker-compose.prod.yml pull
IMAGE_TAG=<good-sha> docker compose -f docker-compose.prod.yml up -d
```

Find a SHA from `git log --oneline` or the Actions run list. Note this does
**not** roll the database back: `db push` is forward-converging, so a rollback
across a destructive schema change needs the backup below.

---

## Troubleshooting

**`ECONNREFUSED` reaching Postgres or Redis.** The host service is not
listening on the bridge. Check `listen_addresses` / `bind`, confirm the bridge
address is what you assumed (`ip -4 addr show docker0`), and check from inside
a container:

```bash
docker compose -f docker-compose.prod.yml exec http-api \
  node -e "require('net').connect(5432,'host.docker.internal').on('connect',()=>{console.log('ok');process.exit(0)}).on('error',e=>{console.log(e.code);process.exit(1)})"
```

**The site loads but nothing works; the browser console shows calls to
`localhost:4001`.** `NEXT_PUBLIC_API_URL` was wrong when the web image was
built. These values are compiled into the client bundle, so fixing the secret
requires a **rebuild**, not a restart — re-run the deploy workflow.

**Battles never start; everything else is fine.** The WebSocket is not being
upgraded. Check in this order:

```bash
# 1. Does the handshake reach ws-server at all? 101 = yes.
curl -i -s -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" -H "Sec-WebSocket-Version: 13" \
  https://api.spidder.example.com/ws | head -1

# 2. Is the map defined? Missing $connection_upgrade is the usual cause.
sudo nginx -T | grep -A3 'map $http_upgrade'
```

A `200` instead of `101` means the request fell through to `location /` and hit
http-api — the `/ws` block is missing or ordered after the catch-all. A `502`
means it routed correctly but ws-server is down.

**`403` or `404` from the API on requests the browser makes.** Usually CORS:
`CORS_ORIGINS` on the server must be the **site** origin
(`https://spidder.example.com`), not the API's own hostname. It is the origin
the browser sends, not the one it is talking to.

**The admin dashboard's live connection count is always zero.**
`WS_SERVER_INTERNAL_URL` must be `http://ws-server:4002` — the code defaults to
`localhost:4002`, which inside a container is the container itself. It is set
in `docker-compose.prod.yml`; confirm it survived any local edit:

```bash
docker compose -f docker-compose.prod.yml exec http-api printenv WS_SERVER_INTERNAL_URL
```

**Submissions queue but never judge.** `judge-worker` or `piston` is down:

```bash
docker compose -f docker-compose.prod.yml logs judge-worker piston
```

`piston-init` must have exited 0 at least once, or no language runtime is
installed and every submission fails to execute.

**`no space left on device` during a pull.** Old images:

```bash
docker system df
docker image prune -a -f --filter "until=168h"
```
