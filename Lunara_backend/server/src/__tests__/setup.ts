import dotenv from 'dotenv';
import sequelize from '../config/database';
import { syncModels } from '../models/index';

dotenv.config({ path: '.env.test' }); // load .env.test if exists
process.env.NODE_ENV = 'test';
process.env.PORT = '5001'; // Avoid conflict with dev server

jest.setTimeout(120000);

beforeAll(async () => {
    // Wait for the database connection
    await sequelize.authenticate();
    // Sync to test db
    await syncModels({ force: true });
});

afterAll(async () => {
    await sequelize.close();
});
