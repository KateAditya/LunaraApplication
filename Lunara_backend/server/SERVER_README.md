# Lunara Server (Backend API)

Node.js/Express backend API with TypeScript for the Lunara platform.

## Quick Start

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your database credentials and API keys
   ```

3. **Ensure PostgreSQL is running and create database:**
   ```bash
   createdb lunara_db
   ```

4. **Start development server:**
   ```bash
   npm run dev
   ```

Server will be available at http://localhost:5000

## Scripts

- `npm run dev` - Development mode with hot reload
- `npm run build` - Compile TypeScript to JavaScript
- `npm start` - Run production build
- `npm test` - Run test suite
- `npm run lint` - Check code quality
- `npm run format` - Format code with Prettier

## Project Structure

```
src/
├── config/          # Configuration (database, logger)
├── controllers/     # Request handlers
├── middleware/      # Express middleware
├── models/          # Database models
├── routes/          # API routes
├── services/        # Business logic & integrations
├── types/           # TypeScript types
├── utils/           # Helper functions
└── server.ts        # Application entry point
```

## API Endpoints (Coming Soon)

- `GET /health` - Health check
- `POST /api/auth/login` - User authentication
- `POST /api/auth/register` - User registration
- `GET /api/venues` - List venues
- `POST /api/bookings` - Create booking
- And more...

## Technologies

- Express.js - Web framework
- TypeScript - Type safety
- Sequelize - PostgreSQL ORM
- Socket.io - Real-time updates
- JWT - Authentication
- Winston - Logging
- Razorpay - Payment processing

## Development Notes

- Database migrations will be added in Phase 2
- API documentation (Swagger) will be added in Phase 3
- Test coverage will be implemented in Phase 6
