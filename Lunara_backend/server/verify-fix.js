const fs = require('fs');
const path = require('path');
const axios = require('axios');
const FormData = require('form-data');
const { Sequelize } = require('sequelize');
const dotenv = require('dotenv');
dotenv.config();

const dummyVideoPath = path.join(__dirname, 'test_final.mp4');
fs.writeFileSync(dummyVideoPath, 'dummy video content for validation');

const sequelize = new Sequelize(process.env.DB_NAME, process.env.DB_USER, process.env.DB_PASSWORD, {
  host: process.env.DB_HOST,
  dialect: 'postgres',
  logging: false,
});

async function verify() {
  try {
    console.log('--- Phase 1: Uploading Video ---');
    const fd = new FormData();
    fd.append('name', 'Verification Venue ' + Date.now());
    fd.append('category', 'club');
    fd.append('addressLine1', '123 Verify St');
    fd.append('city', 'Verify City');
    fd.append('state', 'Verify State');
    fd.append('pincode', '123456');
    fd.append('phone', '0000000000');
    fd.append('standingCapacity', '100');
    fd.append('status', 'pending');
    
    fd.append('videos', fs.createReadStream(dummyVideoPath), {
      filename: 'test_final.mp4',
      contentType: 'video/mp4'
    });

    const response = await axios.post('http://localhost:5000/api/venues', fd, {
      headers: fd.getHeaders()
    });

    const venueId = response.data.venue.id;
    console.log('Venue created with ID:', venueId);

    console.log('--- Phase 2: Verifying Database Record ---');
    const [results] = await sequelize.query(`
      SELECT * FROM venue_images 
      WHERE venue_id = '${venueId}' AND image_type = 'video'
    `);

    if (results.length > 0) {
      console.log('SUCCESS: Video record found in database!');
      console.log('Record:', JSON.stringify(results[0], null, 2));
    } else {
      console.error('FAILURE: No video record found in database for this venue.');
    }

    process.exit(0);
  } catch (err) {
    if (err.response) {
      console.error('API Error:', err.response.status, err.response.data);
    } else {
      console.error('Error:', err.message);
    }
    process.exit(1);
  }
}

verify();
