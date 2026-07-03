# PostgreSQL Connection - Quick Fix Summary

## Current Status: ❌ NOT CONNECTED

**Error:** `no pg_hba.conf entry for host "59.153.120.234", user "postgres", database "postgres", no encryption`

## What Needs to Be Done

You need to configure the PostgreSQL server (103.224.247.22) to allow remote connections.

### Quick Fix (5 Minutes)

**Option 1: If you have SSH access to 103.224.247.22**

SSH into the server and run these commands:

```bash
# 1. Edit pg_hba.conf
sudo nano /etc/postgresql/14/main/pg_hba.conf

# Add this line at the end:
host    all    all    59.153.120.234/32    md5

# 2. Edit postgresql.conf  
sudo nano /etc/postgresql/14/main/postgresql.conf

# Change listen_addresses to:
listen_addresses = '*'

# 3. Restart PostgreSQL
sudo systemctl restart postgresql

# 4. Allow firewall
sudo ufw allow 5432/tcp
```

Then test from your client:
```bash
node test-db-connection.js
```

---

**Option 2: If you DON'T have SSH access**

Contact your server administrator and share the [POSTGRES_SERVER_CONFIG.md](file:///e:/Development/NightView/Lunara_backend/server/POSTGRES_SERVER_CONFIG.md) file.

---

**Option 3: Use SSH Tunnel**

Create an SSH tunnel (requires SSH access but no config changes):
```bash
ssh -L 5432:localhost:5432 username@103.224.247.22 -N
```

Then update `.env`:
```
DB_HOST=localhost
```

---

## Files Created

- ✅ [POSTGRES_SERVER_CONFIG.md](file:///e:/Development/NightView/Lunara_backend/server/POSTGRES_SERVER_CONFIG.md) - Detailed configuration guide
- ✅ [test-db-connection.js](file:///e:/Development/NightView/Lunara_backend/server/test-db-connection.js) - Connection test script  
- ✅ [db-test-log.txt](file:///e:/Development/NightView/Lunara_backend/server/db-test-log.txt) - Latest test results
- ✅ Updated database.ts with SSL support (ready when server supports it)

## Once Connected

After successful connection, we can proceed to **Phase 2: Database Schema & Models** where we'll create:
- User, Venue, Booking models
- Database migrations
- Seed data
- Model relationships

