/** @type {import('ts-jest').JestConfigWithTsJest} */
module.exports = {
    preset: 'ts-jest',
    testEnvironment: 'node',
    testMatch: ['**/__tests__/**/*.test.ts'],
    setupFiles: ['<rootDir>/src/__tests__/setupEnv.ts'],
    setupFilesAfterEnv: ['<rootDir>/src/__tests__/setup.ts'],
    forceExit: true,
    clearMocks: true,
    resetMocks: true,
    restoreMocks: true,
};
