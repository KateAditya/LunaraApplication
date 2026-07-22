import dotenv from 'dotenv';
import path from 'path';

// Resolve path to .env.test in backend server root
dotenv.config({ path: path.resolve(__dirname, '../../.env.test') });
process.env.NODE_ENV = 'test';
process.env.PORT = '5001';
