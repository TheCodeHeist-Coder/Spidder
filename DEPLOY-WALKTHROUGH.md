# Spidder — deployment walkthrough (user: `spidder`)

A start-to-finish run for a VPS that **already has Docker, Postgres and Redis
installed**. You will not reinstall any of them. What follows creates the
`spidder` user, gives it the access it needs, points the app at the databases you
already have, and puts nginx in front.

[DEPLOYMENT.md](DEPLOYMENT.md) is the reference version of all of this — read
it when you want the reasoning. This file is the sequence.

Throughout, replace:

| Placeholder | With |
| --- | --- |
| `spidder.example.com` | the site hostname |
| `api.spidder.example.com` | the API hostname |
| `your.vps.ip` | the server's address |

---

## Stage 0 — What you already have

Run these **as your current user** before changing anything. They tell you what
work is genuinely left.

```bash
# Is Postgres reachable from a container? This is the one that usually fails.
sudo -u postgres psql -c 'SHOW listen_addresses;'

# Redis: bound where, and does it need a password?
sudo grep -E '^\s*(bind|requirepass|protected-mode)' /etc/redis/redis.conf

# Does the app's database already exist?
sudo -u postgres psql -c '\l' | grep -i spidder || echo "spidder: NOT created yet"

# What is the docker bridge address? Every config below refers to it.
ip -4 addr show docker0 | awk '/inet /{print "docker bridge:", $2}'
```

Keep the bridge address (usually `172.17.0.1`) — you need it in stages 2 and 3.

If `listen_addresses` says only `localhost`, **stage 2 is required**. Postgres
being installed is not the same as Postgres being reachable from a container,
and this is the single most common reason a first deploy fails.

---

## Stage 1 — Create the `spidder` user

As root, or any user with sudo:

```bash
sudo adduser --disabled-password --gecos "" spidder
```

No password: you will reach this account by SSH key only, which is what an
account CI drives should be.

### Groups

```bash
sudo usermod -aG sudo spidder      # for setup; not needed for deploys
sudo usermod -aG docker spidder    # this is the one that matters
```

You are **not installing Docker again**. The daemon is already running as root;
the `docker` group is simply the key to its socket at `/var/run/docker.sock`.
Adding `spidder` to that group is the whole of "giving `spidder` Docker access".

> `docker` group membership is effectively root — a member can mount `/` into a
> container and edit anything. That is normal for a deploy account and it is
> what CI needs, but treat the `spidder` SSH key as a root-equivalent credential.

### SSH key

On **your laptop**:

```bash
ssh-keygen -t ed25519 -C "spidder-deploy" -f ~/.ssh/spidder_deploy -N ""
ssh-copy-id -i ~/.ssh/spidder_deploy.pub spidder@your.vps.ip
```

Then verify — this must pass before you go further:

```bash
ssh -i ~/.ssh/spidder_deploy spidder@your.vps.ip 'id'
```

You should see `docker` in the group list. If you don't, the group was added
after the session started; reconnect and check again.

Finally, confirm Docker works **without sudo** as `spidder`:

```bash
ssh -i ~/.ssh/spidder_deploy spidder@your.vps.ip 'docker ps'
```

A "permission denied on /var/run/docker.sock" here means the group has not
taken effect in that session. Log out fully and back in.

---

## Stage 2 — Let containers reach your Postgres

Your containers talk to the host database through `host.docker.internal`, which
resolves to the docker bridge. Postgres must be listening there, and must
accept connections from the bridge subnet.

### Create the role and database

Skip whichever of these you already did.

```bash
sudo -u postgres psql
```

```sql
CREATE ROLE spidder WITH LOGIN PASSWORD 'PUT_A_LONG_RANDOM_PASSWORD_HERE';
CREATE DATABASE spidder OWNER spidder;
\q
```

Generate that password rather than inventing one: `openssl rand -hex 24`.

### Listen on the bridge

```bash
sudo -u postgres psql -c 'SHOW config_file;'     # find the exact path
sudo nano /etc/postgresql/16/main/postgresql.conf
```

```conf
listen_addresses = 'localhost,172.17.0.1'
```

### Allow the bridge subnet

```bash
sudo nano /etc/postgresql/16/main/pg_hba.conf
```

Add this line. It is `172.16.0.0/12`, not the single gateway address, because a
container's own IP is assigned per-network and will not be `172.17.0.1`:

```conf
host    spidder    spidder    172.16.0.0/12    scram-sha-256
```

```bash
sudo systemctl restart postgresql
```

### Prove it works

This is the only test that means anything — it runs from inside a container,
exactly like the app will:

```bash
docker run --rm --add-host=host.docker.internal:host-gateway alpine:3.20 \
  sh -c 'nc -z -w3 host.docker.internal 5432 && echo CONNECTED || echo REFUSED'
```

`REFUSED` means `listen_addresses` has not taken effect. Do not continue until
this prints `CONNECTED`.

---

## Stage 3 — Same for Redis

```bash
sudo nano /etc/redis/redis.conf
```

```conf
bind 127.0.0.1 172.17.0.1
requirepass PUT_ANOTHER_LONG_RANDOM_PASSWORD_HERE
protected-mode yes
appendonly yes
```

```bash
sudo systemctl restart redis-server
```

> **Do set the password.** A Redis on the bridge with no password is reachable
> by anything that gets a shell in any container — including the sandbox whose
> entire job is running strangers' code.

Prove it:

```bash
docker run --rm --add-host=host.docker.internal:host-gateway alpine:3.20 \
  sh -c 'nc -z -w3 host.docker.internal 6379 && echo CONNECTED || echo REFUSED'
```

---

## Stage 4 — Firewall

Only SSH and web need to be open. The app ports are published to `127.0.0.1`
and reached by nginx locally; the database ports are reached over the docker
bridge, which `ufw` does not filter.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
sudo ufw status verbose
```

From your **laptop**, these must all hang and time out:

```bash
nc -zv your.vps.ip 5432
nc -zv your.vps.ip 6379
nc -zv your.vps.ip 4001
```

If any connects, stop and fix it before the app is live.

---

## Stage 5 — Get the code, as `spidder`

```bash
ssh -i ~/.ssh/spidder_deploy spidder@your.vps.ip
```

Clone into the `spidder` user's own home directory. No `sudo`, no `chown` — the
user already owns it, which is the whole point of running deploys as `spidder`:

```bash
cd ~
git clone https://github.com/TheCodeHeist-Coder/Spidder.git app
cd ~/app
pwd          # /home/spidder/app — note this, you need it in stage 11
```

Docker does not care where the compose file lives. The one path-sensitive thing
in it is a bind mount for the Piston provisioning script, and that path is
relative to the compose file, so it travels with the directory.

Tighten the home directory while you are here. Some distros create it `755`,
which would let any other account on the box read your `.env` — and that file
holds the database password and the JWT secret:

```bash
chmod 750 /home/spidder
```

---

## Stage 6 — Write `.env`

```bash
cp .env.prod.example .env
chmod 600 .env
nano .env
```

`chmod 600` matters: this file holds your database password and JWT secret.

Generate the JWT secret now:

```bash
openssl rand -hex 32
```

Six values are **required** — compose refuses to start without them:

```bash
# Note host.docker.internal, NOT localhost. Inside a container, localhost is
# the container itself, and the connection is refused.
DATABASE_URL="postgresql://spidder:YOUR_PG_PASSWORD@host.docker.internal:5432/spidder?schema=public"
REDIS_URL="redis://:YOUR_REDIS_PASSWORD@host.docker.internal:6379"

JWT_SECRET="paste-the-openssl-output-here"

# The SITE origin — the origin a browser sends. Not the API's own hostname.
CORS_ORIGINS="https://spidder.example.com"

# What the BROWSER calls. Compiled into the JS bundle at image build time.
NEXT_PUBLIC_API_URL="https://api.spidder.example.com"
NEXT_PUBLIC_WS_URL="wss://api.spidder.example.com/ws"
```

Note the Redis URL shape: `redis://:password@host` — the colon before the
password is not a typo. Redis has no username, so the field is left empty.

Optional, worth setting on the first deploy so you have an admin account:

```bash
SUPER_ADMIN_EMAIL="you@example.com"
SUPER_ADMIN_PASSWORD="a-strong-password"
SUPER_ADMIN_USERNAME="admin"
```

Remove those three and restart once the account exists, so the credentials stop
sitting in a file on disk.

### Check it before starting anything

```bash
docker compose -f docker-compose.prod.yml config >/dev/null && echo "env OK"
```

A missing required value names itself here, in a second, instead of halfway
through a rollout.

---

## Stage 7 — First start

```bash
cd ~/app
docker compose -f docker-compose.prod.yml up -d
```

The first run pulls five images, installs Python into the Piston sandbox, then
applies the database schema and seeds the problems. Give it a few minutes.

Watch it happen:

```bash
docker compose -f docker-compose.prod.yml logs -f
```

Then confirm the shape is right:

```bash
docker compose -f docker-compose.prod.yml ps
```

You are looking for:

| Service | Expected |
| --- | --- |
| `http-api` | Up (healthy) |
| `ws-server` | Up (healthy) |
| `web` | Up (healthy) |
| `judge-worker` | Up (healthy) |
| `piston` | Up (healthy) |
| `db-init` | **Exited (0)** |
| `piston-init` | **Exited (0)** |

The two `Exited (0)` are correct, not failures — they are one-shot setup jobs
that run and finish. Any other exit code is a real problem; read its log:

```bash
docker compose -f docker-compose.prod.yml logs db-init
```

### Prove the stack works before adding nginx

```bash
curl -s localhost:4001/health          # {"ok":true}
curl -s localhost:4002/health          # {"ok":true}
curl -sI localhost:3001 | head -1      # HTTP/1.1 200 OK
```

All three must pass. If they do, the application is fine and anything that
breaks next is nginx or DNS — which is a much smaller haystack.

---

## Stage 8 — DNS

Point both names at the server, and wait for them to resolve before requesting
certificates. Certbot proves control by answering a challenge on these names.

```
A    spidder.example.com       ->  your.vps.ip
A    api.spidder.example.com   ->  your.vps.ip
```

```bash
dig +short spidder.example.com
dig +short api.spidder.example.com
```

Both must print your server's IP before stage 10.

---

## Stage 9 — nginx, in depth

nginx is the only way in. The containers publish to `127.0.0.1` only, so
without this nothing is reachable from outside the machine at all.

Needs sudo — nginx is a host service, not a container.

### How nginx decides where a request goes

Two rules, and almost every routing surprise comes from misunderstanding one of
them.

**First it picks a `server` block, by `Host` header.** Two hostnames point at
this one IP, so nginx reads the `Host:` header the browser sent and matches it
against `server_name`. That is why the site and the API can share port 443 with
no conflict.

**Then, inside that block, it picks a `location`** — and *not* in file order.
The rules, in priority:

| Syntax | Meaning | Priority |
| --- | --- | --- |
| `location = /path` | exact match | highest — wins immediately |
| `location ^~ /path` | prefix, stop searching regexes | second |
| `location ~ /re` | regex, first match in file order | third |
| `location /path` | prefix — **longest match wins** | lowest |

The last row is the one that catches people. `location /ws` and `location /`
are both prefix matches; `/ws` wins for a request to `/ws` because it is
*longer*, not because it appears first. Writing it first is still worth doing —
it makes the intent obvious to the next reader — but the ordering is not what
makes it work.

### The upgrade map

Must live at `http` level, not inside a `server`, so it goes in its own file:

```bash
sudo nano /etc/nginx/conf.d/upgrade.conf
```

```nginx
# Maps the request's Upgrade header to the right Connection response header.
#
# Why not just write `proxy_set_header Connection "upgrade"` in the /ws block?
# Because that block also serves the plain HTTP requests that share the same
# connection, and telling nginx every one of them is an upgrade breaks
# keep-alive. This sends "upgrade" only when the client actually asked for one.
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
```

### Shared proxy headers

Both blocks set the same four headers. Put them in one file and `include` it,
so they cannot drift apart:

```bash
sudo nano /etc/nginx/conf.d/proxy-common.conf
```

```nginx
# Included by every location that proxies to a container.
#
# Without these the app sees every request as coming from 127.0.0.1 (nginx
# itself) on http — so rate limiting by IP would lump all users together, and
# any absolute URL the app generates would come out as http://.
proxy_set_header Host              $host;
proxy_set_header X-Real-IP         $remote_addr;
proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host  $host;
```

> `conf.d/*.conf` is included at `http` level, so this file is parsed once and
> the directives are available to every server block. `include` inside a
> `location` then pulls them in where needed.

### Rate limiting

Define the zones at `http` level. They are *defined* here and *applied* per
location, which lets one zone protect several endpoints:

```bash
sudo nano /etc/nginx/conf.d/limits.conf
```

```nginx
# 10 MB of shared memory tracks roughly 160,000 addresses — far more than a
# single VPS will ever see at once.
#
# Two zones because the traffic shapes differ. Normal API browsing is bursty
# and harmless; auth endpoints are where credential stuffing lands, and there a
# human never needs more than a few attempts a minute.
limit_req_zone $binary_remote_addr zone=api:10m  rate=30r/s;
limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/m;

# Cap concurrent connections per address. A WebSocket holds one open for the
# length of a battle, so this must be generous enough for several tabs.
limit_conn_zone $binary_remote_addr zone=conn:10m;

# Return 429 rather than nginx's default 503 — "too many requests" is the
# honest status, and clients back off correctly on it.
limit_req_status 429;
limit_conn_status 429;
```

### The site block

```bash
sudo nano /etc/nginx/sites-available/spidder
```

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name spidder.example.com;

    # Hide the nginx version from error pages and the Server header.
    server_tokens off;

    # Security headers. These apply to the HTML the site serves.
    #
    # No Content-Security-Policy here: Next.js injects inline scripts for
    # hydration, and a CSP tight enough to be worth having needs nonces wired
    # through the app. A half-CSP with 'unsafe-inline' would be theatre.
    add_header X-Content-Type-Options "nosniff"        always;
    add_header X-Frame-Options        "SAMEORIGIN"     always;
    add_header Referrer-Policy        "strict-origin-when-cross-origin" always;

    # Uploads are avatars at most.
    client_max_body_size 2m;

    # Next's immutable build assets: hashed filenames, safe to cache forever.
    # `^~` stops nginx evaluating regex locations for these, which is a small
    # win on the highest-volume path on the site.
    location ^~ /_next/static/ {
        proxy_pass http://127.0.0.1:3001;
        include /etc/nginx/conf.d/proxy-common.conf;

        add_header Cache-Control "public, max-age=31536000, immutable";
        access_log off;
    }

    # Everything else: the Next.js server.
    location / {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        include /etc/nginx/conf.d/proxy-common.conf;

        # Next streams server components. Buffering holds the whole response
        # until it completes, which delays first paint for no benefit.
        proxy_buffering off;

        # If the container is restarting mid-deploy, wait rather than 502.
        proxy_connect_timeout 5s;
        proxy_read_timeout    60s;
    }
}
```

### The API block

This one carries the WebSocket, the auth rate limit, and the deny rule for the
unauthenticated internal endpoint.

```bash
sudo nano /etc/nginx/sites-available/spidder-api
```

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name api.spidder.example.com;

    server_tokens off;
    client_max_body_size 2m;

    # Concurrent connections per IP. Generous because each open battle holds a
    # WebSocket, and someone may legitimately have two or three tabs.
    limit_conn conn 20;

    # --- realtime: ws-server -------------------------------------------------
    location /ws {
        proxy_pass http://127.0.0.1:4002;
        proxy_http_version 1.1;

        # The two headers that make an upgrade happen. $connection_upgrade
        # comes from the map in conf.d/upgrade.conf.
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        include /etc/nginx/conf.d/proxy-common.conf;

        # A battle runs for minutes and the socket is idle between moves.
        # nginx's 60s default would cut it mid-match, and the client would
        # reconnect into a battle already in progress.
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;

        # Realtime frames must not wait for a buffer to fill.
        proxy_buffering off;

        # NOT rate limited. A WebSocket is one request that lives for the whole
        # battle; limiting it by request rate would do nothing useful, and
        # limit_conn above already caps how many a single address can hold.
    }

    # --- ws-server health, for uptime monitoring -----------------------------
    # `=` is an exact match, so this cannot accidentally shadow anything.
    location = /ws-health {
        proxy_pass http://127.0.0.1:4002/health;
        include /etc/nginx/conf.d/proxy-common.conf;
        access_log off;
    }

    # --- BLOCKED: unauthenticated internal endpoint --------------------------
    # ws-server exposes /internal/stats with NO auth — by design, because it is
    # meant to be reached only by http-api over the Docker network. See
    # apps/ws-server/src/transport/httpApp.ts.
    #
    # `^~` matters here: it stops nginx searching regex locations, so no regex
    # added later can ever take precedence and re-expose this.
    location ^~ /internal/ {
        return 404;
    }

    # --- auth: the tight rate limit ------------------------------------------
    # 5 requests/minute per IP, burst 10. Credential stuffing is the attack
    # this blunts; a real person signing in never comes close to the limit.
    #
    # `nodelay` lets the burst through immediately rather than queuing it —
    # a legitimate retry should feel instant, only sustained abuse should stall.
    location /auth/ {
        limit_req zone=auth burst=10 nodelay;

        proxy_pass http://127.0.0.1:4001;
        proxy_http_version 1.1;
        include /etc/nginx/conf.d/proxy-common.conf;
        proxy_read_timeout 60s;
    }

    # --- everything else: http-api -------------------------------------------
    location / {
        limit_req zone=api burst=60 nodelay;

        proxy_pass http://127.0.0.1:4001;
        proxy_http_version 1.1;
        include /etc/nginx/conf.d/proxy-common.conf;

        proxy_connect_timeout 5s;
        proxy_read_timeout    60s;
    }
}
```

> **On CORS.** Do not add `add_header Access-Control-Allow-Origin` here. The
> API already handles CORS itself from `CORS_ORIGINS`, and a second set of
> headers from nginx produces *duplicate* headers, which browsers reject
> outright — the symptom is every cross-origin request failing with a CORS
> error that looks like the app is misconfigured.

### Enable and test

```bash
sudo ln -s /etc/nginx/sites-available/spidder     /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/spidder-api /etc/nginx/sites-enabled/

# The default block answers for any Host that matches nothing else. Left in
# place it will serve the nginx welcome page to anyone hitting your bare IP.
sudo rm -f /etc/nginx/sites-enabled/default

sudo nginx -t
```

`nginx -t` is not optional. A reload with a broken config leaves the old one
running — but a *restart* would fail and take the site down.

```bash
sudo systemctl reload nginx
```

### Check the routing before adding TLS

Over plain HTTP first, so a certificate problem cannot be confused with a
routing problem. `--resolve` forces the hostname at your server without
needing DNS to have propagated yet:

```bash
IP=your.vps.ip

curl -s --resolve spidder.example.com:80:$IP \
  -o /dev/null -w 'site:      %{http_code}\n' http://spidder.example.com/

curl -s --resolve api.spidder.example.com:80:$IP \
  http://api.spidder.example.com/health && echo

curl -s --resolve api.spidder.example.com:80:$IP \
  http://api.spidder.example.com/ws-health && echo

# MUST be 404.
curl -s --resolve api.spidder.example.com:80:$IP \
  -o /dev/null -w 'internal:  %{http_code} (must be 404)\n' \
  http://api.spidder.example.com/internal/stats
```

### Useful while debugging

```bash
# The whole effective config, every include expanded. Answers "is my map
# actually loaded" definitively.
sudo nginx -T | less

# Confirm the upgrade map is present.
sudo nginx -T | grep -A3 'map $http_upgrade'

# Which server block answered, and what it did.
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

An `upstream connect failed` in the error log means nginx is fine and the
container is not — check `docker compose ps`.

---

## Stage 10 — HTTPS

```bash
sudo certbot --nginx \
  -d spidder.example.com \
  -d api.spidder.example.com \
  --agree-tos -m you@example.com --redirect
```

Certbot edits both server blocks in place, adding `listen 443 ssl`, the
certificate paths, and an HTTP→HTTPS redirect. Renewal is a systemd timer:

```bash
sudo certbot renew --dry-run
systemctl list-timers | grep certbot
```

### Verify the whole path

```bash
curl -sI https://spidder.example.com | head -1                  # 200
curl -s  https://api.spidder.example.com/health                 # {"ok":true}
curl -s  https://api.spidder.example.com/ws-health              # {"ok":true}

# MUST be 404. A 200 means the deny block is missing or mis-ordered.
curl -s -o /dev/null -w '%{http_code}\n' \
     https://api.spidder.example.com/internal/stats

# The WebSocket. 101 Switching Protocols means the handshake works.
curl -i -s -N \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  -H "Sec-WebSocket-Version: 13" \
  https://api.spidder.example.com/ws | head -1
```

That `101` is the single most important check here. A `200` instead means the
request fell through to http-api — the `/ws` block is missing or ordered after
`location /`.

Then open the site in a browser, sign in, and start a battle. If the timer
runs and a submission gets judged, the whole path works.

---

## Stage 11 — CI/CD

Add these under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `DOCKERHUB_USERNAME` | `codeheist` |
| `DOCKERHUB_TOKEN` | access token from hub.docker.com → Account Settings → Personal access tokens (Read & Write) |
| `VPS_HOST` | `your.vps.ip` |
| `VPS_USER` | `spidder` |
| `VPS_SSH_KEY` | the **whole** contents of `~/.ssh/spidder_deploy` (private key) |
| `VPS_APP_DIR` | `/home/spidder/app` — **absolute**, not `~/app` |
| `NEXT_PUBLIC_API_URL` | `https://api.spidder.example.com` |
| `NEXT_PUBLIC_WS_URL` | `wss://api.spidder.example.com/ws` |

```bash
cat ~/.ssh/spidder_deploy      # copy everything, BEGIN and END lines included
```

Note `VPS_USER` is `spidder`, and `NEXT_PUBLIC_*` must match what you put in
`.env` — they are compiled into the browser bundle at image build time, so a
mismatch means the site calls the wrong host and only a rebuild fixes it.

### First run

Push to `main`, or use **Actions → Deploy → Run workflow**. It will:

1. re-run lint, typecheck and tests
2. build five images and push them to Docker Hub
3. SSH in as `spidder`, pull, apply the schema, restart

On Docker Hub, the free tier allows **one private repository**. Five private
images needs a paid plan — otherwise make the five repos public. They hold only
compiled application code; every credential is injected at runtime from `.env`.

### Prove the pipeline, not just the app

Change something visible, push, and confirm the running image actually moved:

```bash
docker compose -f docker-compose.prod.yml images | grep web
```

The tag should be the new commit SHA.

---

## Day-to-day

As `spidder`, no sudo:

```bash
cd ~/app
alias dc='docker compose -f docker-compose.prod.yml'

dc ps                     # status and health
dc logs -f --tail=100     # everything
dc logs -f judge-worker   # one service
dc restart http-api
```

Host services need sudo:

```bash
sudo systemctl status nginx postgresql redis-server
sudo nginx -t && sudo systemctl reload nginx
sudo tail -f /var/log/nginx/error.log
```

### Backups

The database is on the host, so no Docker volume contains it:

```bash
sudo tee /etc/cron.daily/spidder-backup >/dev/null <<'EOF'
#!/bin/sh
set -eu
mkdir -p /var/backups/spidder
sudo -u postgres pg_dump spidder | gzip \
  > /var/backups/spidder/spidder-$(date +%F).sql.gz
find /var/backups/spidder -name '*.sql.gz' -mtime +14 -delete
EOF
sudo chmod +x /etc/cron.daily/spidder-backup
sudo /etc/cron.daily/spidder-backup && ls -lh /var/backups/spidder
```

Run it once by hand as above — a backup script nobody has tested is not a
backup.

### Rollback

Re-run **Deploy** on the last good commit from the Actions tab, or pin by hand:

```bash
cd ~/app
IMAGE_TAG=<good-sha> docker compose -f docker-compose.prod.yml pull
IMAGE_TAG=<good-sha> docker compose -f docker-compose.prod.yml up -d
```

This rolls back **code only**. `prisma db push` converges forward, so undoing a
destructive schema change needs the backup above.

---

## When something breaks

**`docker ps` says permission denied.** The `docker` group has not applied to
this session. Log out completely and back in.

**Containers restart in a loop.** Read the log — it names the missing thing:

```bash
docker compose -f docker-compose.prod.yml logs --tail=50 http-api
```

**`ECONNREFUSED` to Postgres or Redis.** Almost always `localhost` in `.env`
where it should be `host.docker.internal`, or the host service still listening
on loopback only. Test from inside a container:

```bash
docker compose -f docker-compose.prod.yml exec http-api \
  node -e "require('net').connect(5432,'host.docker.internal').on('connect',()=>{console.log('ok');process.exit(0)}).on('error',e=>{console.log(e.code);process.exit(1)})"
```

**Site loads, but the browser console shows calls to `localhost:4001`.**
`NEXT_PUBLIC_API_URL` was wrong when the image was built. It is compiled into
the bundle — re-run the deploy workflow with the corrected secret. A restart
will not fix it.

**Battles never start, everything else is fine.** The WebSocket is not
upgrading. Check the `101` from stage 10, then:

```bash
sudo nginx -T | grep -A3 'map $http_upgrade'
```

**Submissions queue but are never judged.** `judge-worker` or `piston` is down,
or Piston has no Python runtime:

```bash
docker compose -f docker-compose.prod.yml logs judge-worker piston
docker compose -f docker-compose.prod.yml logs piston-init | tail -5
```

**`no space left on device`.** Old images:

```bash
docker system df
docker image prune -a -f --filter "until=168h"
```

---

## One gap to know about

`apps/admin` has **no Dockerfile**, so the separate admin UI is not deployable
yet and nothing above proxies to it. The admin *API* routes live inside
`http-api` and are already served from `api.spidder.example.com`; only the
Next.js dashboard is missing. When it is containerised it needs its own
hostname, its own server block, and ideally an IP allowlist or basic auth at
the nginx layer on top of its login.
