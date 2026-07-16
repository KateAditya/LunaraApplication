const date = new Date("2026-07-19T14:30:00.000Z");
const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Kolkata',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false
});
const parts = formatter.formatToParts(date);
console.log('Parts:', parts);
const getPart = (type) => parts.find(p => p.type === type)?.value || '';
console.log('Parsed:', {
    year: parseInt(getPart('year'), 10),
    month: parseInt(getPart('month'), 10) - 1,
    day: parseInt(getPart('day'), 10),
    hour: parseInt(getPart('hour'), 10),
    minute: parseInt(getPart('minute'), 10)
});
