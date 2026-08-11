# Clients

## Installed workstation clients

After an [SSH tunnel](ssh-tunnels.md):

- `psql`, DBeaver, or pgAdmin: `127.0.0.1:5432`, database/user/password from `.env`.
- `redis-cli` or RedisInsight: `127.0.0.1:6379`, password from `.env`, no username.
- MongoDB Compass: `mongodb://infra:PASSWORD@127.0.0.1:27017/?authSource=admin`.
- Browser: MinIO console at `http://127.0.0.1:9001`.

Transport inside the Docker network and localhost mapping is plaintext unless you add a separately reviewed TLS layer.

## Optional browser UIs

They never start through base `make up`:

```bash
make clients          # CloudBeaver, RedisInsight, Mongo Express
make clients-pgadmin  # same plus pgAdmin profile
```

| UI | Default localhost port | Internal database hostname |
|---|---:|---|
| CloudBeaver | 8978 | `postgres` |
| pgAdmin | 5050 | `postgres` |
| RedisInsight | 5540 | `redis` |
| Mongo Express | 8081 | `mongo` |

All UI ports remain loopback-bound. Browser UIs increase attack surface; prefer installed clients over SSH when practical. MinIO's built-in console covers the S3 UI use case.
