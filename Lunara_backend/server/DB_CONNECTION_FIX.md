# PostgreSQL Connection Issue - Diagnosis & Solution

## Problem Identified

❌ **Connection Test Failed**

The PostgreSQL server at `103.224.247.22` is **rejecting remote connections** from your client IP.

### Error Details:
```
Error: no pg_hba.conf entry for host "59.153.120.234", 
       user "postgres", 
       database "postgres", 
       no encryption
Code: 28000 (Authentication Failed)
```

### What this means:
PostgreSQL's authentication configuration (`pg_hba.conf`) is not allowing connections from your client IP address (59.153.120.234) without SSL encryption.

---

## Solutions

You need to configure PostgreSQL on the server (103.224.247.22) to allow remote connections. Here are three approaches:

### ✅ Solution 1: Enable SSL Connection (RECOMMENDED - Most Secure)

Update the connection to use SSL:

**Update `.env` file:**
```env
DB_HOST=103.224.247.22
DB_PORT=5432
DB_NAME=lunara_db
DB_USER=postgres
DB_PASSWORD=JaiGanesh2025
DB_SSL=true
```

**Update `src/config/database.ts`:** (Add SSL option)
```typescript
const sequelize = new Sequelize({
  // ... existing config
  dialectOptions: {
    ssl: {
      require: true,
      rejectUnauthorized: false  // Use true in production with proper certificates
    }
  }
});
```

---

### ✅ Solution 2: Configure pg_hba.conf (Requires Server Access)

If you have SSH access to the PostgreSQL server (103.224.247.22), you can modify the configuration:

**1. SSH into the server:**
```bash
ssh user@103.224.247.22
```

**2. Edit pg_hba.conf:**
```bash
sudo nano /etc/postgresql/14/main/pg_hba.conf
# or
sudo nano /var/lib/pgsql/data/pg_hba.conf
```

**3. Add entry to allow your client IP:**
```conf
# Allow connection from your client IP
host    all             all             59.153.120.234/32       md5

# Or allow from any IP (LESS SECURE - use with caution)
host    all             all             0.0.0.0/0               md5
```

**4. Edit postgresql.conf to allow remote connections:**
```bash
sudo nano /etc/postgresql/14/main/postgresql.conf
```

Find and change:
```conf
listen_addresses = '*'
```

**5. Restart PostgreSQL:**
```bash
sudo systemctl restart postgresql
# or
sudo service postgresql restart
```

**6. Check firewall allows port 5432:**
```bash
sudo ufw allow 5432/tcp
# or
sudo firewall-cmd --permanent --add-port=5432/tcp
sudo firewall-cmd --reload
```

---

### ✅ Solution 3: Use SSH Tunnel (Secure Alternative)

If you can't modify server configuration, create an SSH tunnel:

**1. Create SSH tunnel:**
```bash
ssh -L 5432:localhost:5432 user@103.224.247.22 -N
```

**2. Update `.env` to connect via localhost:**
```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=lunara_db
DB_USER=postgres
DB_PASSWORD=JaiGanesh2025
```

This makes PostgreSQL think the connection is local, bypassing the pg_hba.conf restriction.

---

## Quick Test After Fix

After applying any solution, test again:

```bash
cd e:\Development\NightView\Lunara_backend\server
node test-db-connection.js
```

You should see:
```
SUCCESS: Connected to PostgreSQL!
PostgreSQL Version: ...
Existing Databases: ...
Database "lunara_db" created successfully!
```

---

## Recommended Next Steps

1. **Choose a solution** based on your server access and security requirements
2. **Implement the fix** on the PostgreSQL server or connection config
3. **Test connection** using `node test-db-connection.js`
4. **Once successful**, proceed to Phase 2 (Database Schema & Models)

---

## Need Help?

If you need assistance:
- Confirm if you have SSH access to the server (103.224.247.22)
- Let me know which solution you'd like to implement
- I can update the connection configuration files accordingly
