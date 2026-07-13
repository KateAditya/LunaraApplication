import dotenv from 'dotenv';
import sequelize from '../config/database';
import { syncModels } from '../models/index';

dotenv.config({ path: '.env.test' }); // load .env.test if exists
process.env.NODE_ENV = 'test';
process.env.PORT = '5001'; // Avoid conflict with dev server

jest.setTimeout(120000);

beforeAll(async () => {
    // Safety check: Never run force sync on a database unless it is explicitly named as a test database
    const dbName = sequelize.config.database;
    const isExplicitTestDb = dbName.endsWith('_test') || dbName === 'lunara_test' || dbName === 'test';
    
    if (!isExplicitTestDb) {
        console.error(`\n======================================================================`);
        console.error(`❌ CRITICAL SAFETY BLOCK: Refusing to run tests on database "${dbName}"!`);
        console.error(`Running tests will call sync({ force: true }), which drops all tables.`);
        console.error(`To protect your data, please use a database named "lunara_test" or`);
        console.error(`create a ".env.test" file with a dedicated test database configuration.`);
        console.error(`======================================================================\n`);
        process.exit(1);
    }

    // Wait for the database connection
    await sequelize.authenticate();
    // Sync to test db
    await syncModels({ force: true });
});

afterAll(async () => {
    await sequelize.close();
});
