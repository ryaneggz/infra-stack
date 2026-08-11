# SSH tunnels

The VM exposes database ports only on its loopback interface. From a workstation:

```bash
scripts/tunnel.sh --dry-run deploy@example-vm postgres redis mongo
scripts/tunnel.sh deploy@example-vm
LOCAL_PORT_OFFSET=10000 scripts/tunnel.sh deploy@example-vm postgres
```

Omitting services tunnels all five core mappings: PostgreSQL, Redis, MinIO API, MinIO console, and MongoDB. Accepted names are `postgres`, `redis`, `minio`, `minio-console`, `mongo`, `cloudbeaver`, `pgadmin`, `redisinsight`, and `mongo-express`.

The helper validates `user@host`, service names, duplicate/out-of-range ports, and local collisions when Python is available. SSH uses `ExitOnForwardFailure=yes`, a 30-second keepalive, and a three-miss limit. VM endpoints remain `127.0.0.1:<configured-port>`.

After tunneling, connect workstation clients to `127.0.0.1` and the local port. Use `LOCAL_PORT_OFFSET` when a standard local port is occupied. SSH authenticates the tunnel; database credentials still come from the VM's `.env` and transit the tunnel.
