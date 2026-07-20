const fs = require('fs');
const file = 'e:\\lunara_app\\lunara_app\\lib\\services\\api_service.dart';
const content = fs.readFileSync(file, 'utf8');
const lines = content.split('\n');
const query = 'fetchMyLargePartyBookings';
lines.forEach((line, idx) => {
    if (line.includes(query)) {
        console.log(`${idx + 1}: ${line}`);
    }
});
