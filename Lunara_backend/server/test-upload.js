const fs = require('fs');
const path = require('path');
const axios = require('axios');
const FormData = require('form-data');
const dotenv = require('dotenv');
dotenv.config();

// Create a dummy video file
const dummyVideoPath = path.join(__dirname, 'test.mp4');
fs.writeFileSync(dummyVideoPath, 'dummy video content');

async function testUpload() {
  try {
    const fd = new FormData();
    fd.append('name', 'Video Test Venue ' + Date.now());
    fd.append('category', 'club');
    fd.append('addressLine1', '123 Test St');
    fd.append('city', 'Testville');
    fd.append('state', 'Test State');
    fd.append('pincode', '123456');
    fd.append('phone', '1234567890');
    fd.append('standingCapacity', '100');
    fd.append('status', 'pending');
    
    fd.append('videos', fs.createReadStream(dummyVideoPath), {
      filename: 'test.mp4',
      contentType: 'video/mp4'
    });

    console.log('Sending request...');
    const response = await axios.post('http://localhost:5000/api/venues', fd, {
      headers: {
        ...fd.getHeaders(),
        // Needs a valid user or auth token? Let's assume auth is disabled in test or we need a token.
      }
    });

    console.log('Success:', response.data);
  } catch (err) {
    if (err.response) {
      console.error('API Error:', err.response.status, err.response.data);
    } else {
      console.error('Request Error:', err.message);
    }
  }
}
testUpload();
