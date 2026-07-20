const fs = require('fs');
const file = 'e:\\lunara_app\\lunara_app\\lib\\screens\\social\\live_feed_screen.dart';
const content = fs.readFileSync(file, 'utf8');
const lines = content.split('\n');
const query = '_initiateLargePartyPayment';
lines.forEach((line, idx) => {
    if (line.includes(query)) {
        console.log(`${idx + 1}: ${line}`);
    }
});
