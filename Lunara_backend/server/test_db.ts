import { Sequelize } from 'sequelize';

async function test() {
  const sequelize = new Sequelize('postgres://postgres:postgres@localhost:5432/lunara_db', { logging: false });
  try {
    const [results] = await sequelize.query('SELECT going_mode, is_group_booking, is_large_party_request, is_upcoming_night, booking_date FROM bookings LIMIT 10');
    console.log(results);
  } catch(e) {
    console.error(e);
  }
  process.exit(0);
}

test();
