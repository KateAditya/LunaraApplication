/**
 * restore_db_remote.js
 * Sends the local SQL dump to the production server's /api/db-restore endpoint in chunks.
 * Run: node restore_db_remote.js
 */
const fs = require('fs');
const https = require('https');

const API_BASE = 'https://lunara-api-server-a8gfdvg0hjdec6gx.centralindia-01.azurewebsites.net';
const SECRET = 'lunara-bootstrap-2026';
const SQL_FILE = __dirname + '/lunara_db_restore.sql';
const CHUNK_SIZE = 50; // statements per request

function postJson(url, body) {
    return new Promise((resolve, reject) => {
        const data = JSON.stringify(body);
        const urlObj = new URL(url);
        const options = {
            hostname: urlObj.hostname,
            path: urlObj.pathname,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(data),
            },
        };
        const req = https.request(options, (res) => {
            let raw = '';
            res.on('data', (chunk) => (raw += chunk));
            res.on('end', () => {
                try { resolve({ status: res.statusCode, body: JSON.parse(raw) }); }
                catch { resolve({ status: res.statusCode, body: raw }); }
            });
        });
        req.on('error', reject);
        req.write(data);
        req.end();
    });
}

async function main() {
    const sqlRaw = fs.readFileSync(SQL_FILE, 'utf8');

    // Split into SQL statements (semicolon-terminated lines)
    const statements = sqlRaw
        .split(/;\s*\n/)
        .map(s => s.trim())
        .filter(s => s.length > 0 && !s.startsWith('--') && !s.startsWith('\\'));

    console.log(`Total statements: ${statements.length}`);

    let totalExecuted = 0;
    let totalErrors = 0;
    const chunks = [];
    for (let i = 0; i < statements.length; i += CHUNK_SIZE) {
        chunks.push(statements.slice(i, i + CHUNK_SIZE));
    }
    console.log(`Sending in ${chunks.length} chunks of ${CHUNK_SIZE} statements each...`);

    for (let i = 0; i < chunks.length; i++) {
        const sql = chunks[i].join(';\n');
        process.stdout.write(`Chunk ${i + 1}/${chunks.length}... `);
        try {
            const result = await postJson(`${API_BASE}/api/db-restore/restore`, { secret: SECRET, sql });
            if (result.body && result.body.executed !== undefined) {
                totalExecuted += result.body.executed;
                const errs = (result.body.errors || []).length;
                totalErrors += errs;
                process.stdout.write(`✓ (${result.body.executed}/${result.body.totalStatements} executed, ${errs} skipped)\n`);
                if (errs > 0) {
                    console.log('  Skipped:', result.body.errors.slice(0, 3));
                }
            } else {
                console.log(`✗ Status ${result.status}:`, result.body);
            }
        } catch (err) {
            console.log(`✗ Network error: ${err.message}`);
        }
        // Small delay between chunks
        await new Promise(r => setTimeout(r, 200));
    }

    console.log(`\n✅ Done! Total executed: ${totalExecuted}, Skipped: ${totalErrors}`);
}

main().catch(console.error);
