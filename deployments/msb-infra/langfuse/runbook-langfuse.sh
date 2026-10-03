#!/usr/bin/env bash
# Bring Langfuse up inside the infra sandbox.
# NOT RUN AUTOMATICALLY. Step 1 takes infra-postgres down for ~1 minute, and the
# prod app is live against it.
#
# prod is NOT touched: it sends nothing to Langfuse.
set -euo pipefail

IMAGE=ghcr.io/ryaneggz/msb-ubuntu-dind:latest
LF_DIR=/home/dev/infra-services/langfuse

# ---------- Step 1: recreate infra with more RAM and the Langfuse forward ----------
# Why recreate: -p and --net-rule are create-time only (`msb modify` has neither),
# and --max-memory is a boot-time ceiling.
#
# Port forwards:
#   5432/5433 -> shared postgres (5432 is what prod uses via 172.16.0.5)
#   3100      -> langfuse-web (guest 3000); reach it with
#                  ssh -L 3100:127.0.0.1:3100 <this-host>
#   6379/9000 -> RESERVED for a future shared redis / minio. Inert today: no
#                guest process listens there, so the forward goes nowhere.
#                (Same harmless state as prod's existing 3000/3005 forwards.)
#                Reserving now avoids another recreate when you promote them.
msb rm -f infra
rm -rf ~/.microsandbox/sandboxes/infra     # clears any partial state dir
msb create "$IMAGE" \
  --name infra \
  --cpus 4 --max-cpus 4 --memory 6G --max-memory 8G \
  --root-disk 12G \
  --tmpfs /tmp:512M \
  --mount-dir /opt/infra-services:/home/dev/infra-services \
  --mount-named "infra-docker-data:/var/lib/docker:kind=disk,size=30G" \
  --net-rule "allow@dns,allow@public,allow@private" \
  --net-rule "allow:ingress@private" \
  -p 127.0.0.1:5433:5432 \
  -p 127.0.0.1:5432:5432 \
  -p 127.0.0.1:3100:3000 \
  -p 127.0.0.1:6379:6379 \
  -p 127.0.0.1:9000:9000

# ---------- Step 2: start dockerd by hand ----------
# The image entrypoint does not run on boot in this sandbox -- known gap.
msb exec infra -- sh -c 'nohup /usr/local/bin/entrypoint.sh dockerd >/tmp/ep.log 2>&1 &'
until msb exec infra -- test -S /var/run/docker.sock 2>/dev/null; do sleep 5; done
msb exec infra -- docker ps --format '{{.Names}} {{.Status}}'   # infra-postgres must be back

# ---------- Step 3: secrets (you do this) ----------
#   cd /opt/infra-services/langfuse && cp env.template .env && chmod 600 .env
#   openssl rand -hex 32     # once per CHANGE_ME; ENCRYPTION_KEY must be 64 hex

# ---------- Step 4: create the Langfuse role + database on shared postgres ----------
#   msb exec infra -- docker exec -i infra-postgres \
#     psql -U postgres -v pw="'<LANGFUSE_DB_PASSWORD>'" -f - \
#     < /opt/infra-services/langfuse/bootstrap.sql

# ---------- Step 5: start Langfuse ----------
msb exec infra -- sh -c "cd $LF_DIR && docker compose up -d"

# ---------- Step 6: verify ----------
msb exec infra -- sh -c "cd $LF_DIR && docker compose ps"
curl -s -o /dev/null -w 'langfuse http=%{http_code}\n' http://127.0.0.1:3100/api/public/health
# Then: ssh -L 3100:127.0.0.1:3100 <this-host>, open http://localhost:3100,
# create your user, set LANGFUSE_DISABLE_SIGNUP=true in .env, `up -d` again.
