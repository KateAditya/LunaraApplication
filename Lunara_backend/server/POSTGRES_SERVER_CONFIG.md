# PostgreSQL Server Configuration Guide

## Current Situation

The PostgreSQL server at `103.224.247.22` needs to be configured to allow remote connections.

**Issues Identified:**
1. ❌ Server doesn't support SSL connections
2. ❌ pg_hba.conf blocking remote connections from client IP (59.153.120.234)

---

## Server-Side Configuration Steps

### Step 1: SSH into the PostgreSQL Server

```bash
ssh username@103.224.247.22
```

### Step 2: Edit pg_hba.conf

```bash
# Find PostgreSQL version and config location
sudo -u postgres psql -c "SHOW config_file;"

# Common locations:
# /etc/postgresql/14/main/pg_hba.conf   (Ubuntu/Debian)
# /var/lib/pgsql/data/pg_hba.conf       (CentOS/RHEL)

# Edit the file
sudo nano /etc/postgresql/14/main/pg_hba.conf
```

**Add these lines** at the end of the file:

```conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Allow specific client IP (MORE SECURE)
host    all             all             59.153.120.234/32       md5

# Or allow any IP (LESS SECURE - only for development)
host    all             all             0.0.0.0/0               md5
```

**Explanation:**
- `host` = TCP/IP connection
- `all` (database) = all databases
- `all` (user) = all users
- `59.153.120.234/32` = your client IP address
- `md5` = password authentication method

### Step 3: Edit postgresql.conf

```bash
sudo nano /etc/postgresql/14/main/postgresql.conf
```

**Find and modify:**
```conf
# Change from
listen_addresses = 'localhost'

# To
listen_addresses = '*'
```

This tells PostgreSQL to listen on all network interfaces.

### Step 4: Configure Firewall

```bash
# For UFW (Ubuntu)
sudo ufw allow 5432/tcp
sudo ufw reload

# For firewalld (CentOS/RHEL)
sudo firewall-cmd --permanent --add-port=5432/tcp
sudo firewall-cmd --reload

# For iptables
sudo iptables -A INPUT -p tcp --dport 5432 -j ACCEPT
sudo service iptables save
```

### Step 5: Restart PostgreSQL

```bash
# Ubuntu/Debian
sudo systemctl restart postgresql

# CentOS/RHEL
sudo systemctl restart postgresql-14

# Or generic
sudo service postgresql restart
```

### Step 6: Verify Configuration

```bash
# Check if PostgreSQL is listening on all interfaces
sudo netstat -plunt | grep 5432

# Should show:
# tcp  0  0.0.0.0:5432  0.0.0.0:*  LISTEN  12345/postgres
```

---

## Security Recommendations

⚠️ **IMPORTANT**: Since SSL is not enabled, the connection is **NOT ENCRYPTED**.

### For Production:

1. **Enable SSL on PostgreSQL Server:**
   ```bash
   # Generate SSL certificate
   sudo openssl req -new -x509 -days 365 -nodes -text \
     -out /etc/postgresql/14/main/server.crt \
     -keyout /etc/postgresql/14/main/server.key \
     -subj "/CN=103.224.247.22"
   
   # Set permissions
   sudo chmod 600 /etc/postgresql/14/main/server.key
   sudo chown postgres:postgres /etc/postgresql/14/main/server.*
   
   # Edit postgresql.conf
   ssl = on
   ssl_cert_file = '/etc/postgresql/14/main/server.crt'
   ssl_key_file = '/etc/postgresql/14/main/server.key'
   
   # Restart PostgreSQL
   sudo systemctl restart postgresql
   ```

2. **Restrict IP Access:**
   - Update pg_hba.conf to only allow specific IP addresses
   - Use VPN or SSH tunnel for remote access

3. **Use Strong Passwords:**
   - Change default postgres password
   - Use complex passwords for all users

4. **Regular Updates:**
   - Keep PostgreSQL updated
   - Apply security patches

---

## Testing After Configuration

After making changes on the server, test from your client:

```bash
cd e:\Development\NightView\Lunara_backend\server
node test-db-connection.js
```

**Expected Output:**
```
============================================================
PostgreSQL Connection Test
============================================================
Host: 103.224.247.22
Port: 5432
User: postgres
Database: postgres (default)

Connecting...
SUCCESS: Connected to PostgreSQL!

PostgreSQL Version:
...

Existing Databases:
  - lunara_db
  - postgres
  - template0
  - template1

============================================================
TEST RESULT: SUCCESS
============================================================
```

---

## Quick Commands Reference

```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# View PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-14-main.log

# Connect locally to test
sudo -u postgres psql

# List all databases
sudo -u postgres psql -c "\\l"

# List all users
sudo -u postgres psql -c "\\du"
```

---

## Alternative: SSH Tunnel (If you can't modify server config)

If you don't have permission to modify server configuration:

```bash
# Terminal 1: Create SSH tunnel (keep running)
ssh -L 5432:localhost:5432 username@103.224.247.22 -N

# Terminal 2: Update .env
DB_HOST=localhost
DB_PORT=5432
# ... rest of config

# Run test
node test-db-connection.js
```

---

## Next Steps

1. Choose which approach to use
2. Apply the configuration on the server
3. Test the connection
4. Once successful, proceed to Phase 2: Database Schema & Models

