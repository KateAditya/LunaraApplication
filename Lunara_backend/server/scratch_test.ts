process.env.TZ = 'UTC';
import { validateVenueTimingAndHolidays } from './src/utils/venueValidator';

const venue = {
    name: 'Sash',
    openingTime: '15:00:00',
    closingTime: '23:00:00',
    daysOpen: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    closedDates: []
};

console.log('Without Z (TZ=UTC):', validateVenueTimingAndHolidays(venue, '2026-07-19T20:00:00.000'));
console.log('With Z (TZ=UTC):', validateVenueTimingAndHolidays(venue, '2026-07-19T20:00:00.000Z'));
