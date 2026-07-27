const axios = require('axios');

async function test() {
  try {
    const res = await axios.get('http://103.224.247.35:9076/api/admin/payments/summary', {
      headers: { Authorization: 'Bearer demo-access-token' }
    });
    console.log("RESPONSE:", res.status, JSON.stringify(res.data, null, 2));
  } catch (err) {
    if (err.response) {
      console.log("ERROR RESPONSE:", err.response.status, err.response.data);
    } else {
      console.log("FULL ERROR:", err);
    }
  }
}

test();
