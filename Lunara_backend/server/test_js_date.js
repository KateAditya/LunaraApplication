const dateStr = "2026-07-19T20:00:00.000";
const date = new Date(dateStr);
console.log('Date:', date.toString());
console.log('ISO:', date.toISOString());
console.log('Hours (Local):', date.getHours());
console.log('Hours (UTC):', date.getUTCHours());
