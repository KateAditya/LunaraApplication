const http = require('http');
const server = http.createServer();
server.listen(9076, '103.224.247.35', () => {
  console.log('Listening...');
});
server.on('error', (err) => {
  console.error('Error:', err.message);
});
