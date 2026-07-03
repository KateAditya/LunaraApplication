# Lunara Backend

Backend infrastructure for the Lunara/NightVenue platform - A comprehensive B2B2C digital platform for nightlife venue discovery, booking, and management.

## 📁 Project Structure

```
Lunara_backend/
├── server/                 # Node.js/Express backend API
│   ├── src/
│   │   ├── config/        # Configuration files (database, logger)
│   │   ├── controllers/   # Business logic controllers
│   │   ├── middleware/    # Express middleware
│   │   ├── models/        # Database models (Sequelize)
│   │   ├── routes/        # API route definitions
│   │   ├── services/      # External service integrations
│   │   ├── types/         # TypeScript type definitions
│   │   ├── utils/         # Helper utilities
│   │   └── server.ts      # Main application entry point
│   ├── package.json
│   ├── tsconfig.json
│   └── .env.example
│
└── admin-panel/           # React admin interface
    ├── src/
    │   ├── components/    # Reusable UI components
    │   ├── pages/         # Page components
    │   ├── services/      # API integration services
    │   ├── context/       # Global state management
    │   ├── utils/         # Helper functions
    │   └── App.tsx        # Main app component
    ├── package.json
    └── vite.config.ts
```

## 🚀 Getting Started

### Prerequisites

- Node.js (v18 or higher)
- PostgreSQL (v14 or higher)
- npm or yarn package manager

### Backend Server Setup

1. **Navigate to server directory:**
   ```bash
   cd server
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Configure environment:**
   - Copy `.env.example` to `.env`
   - Update database credentials and other configuration
   ```bash
   cp .env.example .env
   ```

4. **Setup PostgreSQL database:**
   ```bash
   # Create database
   createdb lunara_db
   
   # Or using psql
   psql -U postgres
   CREATE DATABASE lunara_db;
   \q
   ```

5. **Run development server:**
   ```bash
   npm run dev
   ```

   The server will start on http://localhost:5000

### Admin Panel Setup

1. **Navigate to admin panel directory:**
   ```bash
   cd admin-panel
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Run development server:**
   ```bash
   npm run dev
   ```

   The admin panel will start on http://localhost:5173

## 🔧 Development

### Backend (Server)

**Available Scripts:**
- `npm run dev` - Start development server with hot reload
- `npm run build` - Build TypeScript to JavaScript
- `npm start` - Run production build
- `npm run lint` - Run ESLint
- `npm run format` - Format code with Prettier
- `npm test` - Run tests

**API Documentation:**
- Swagger/OpenAPI docs available at: http://localhost:5000/api-docs (coming soon)

### Admin Panel

**Available Scripts:**
- `npm run dev` - Start development server
- `npm run build` - Build for production
- `npm run preview` - Preview production build
- `npm run lint` - Run ESLint

## 📦 Tech Stack

### Backend
- **Runtime:** Node.js with Express.js
- **Language:** TypeScript
- **Database:** PostgreSQL with Sequelize ORM
- **Real-time:** Socket.io
- **Authentication:** JWT (JSON Web Tokens)
- **Payment:** Razorpay integration
- **Security:** Helmet, CORS, Rate limiting
- **Logging:** Winston

### Admin Panel
- **Framework:** React 19 with TypeScript
- **Build Tool:** Vite
- **Routing:** React Router v7
- **API Client:** Axios
- **Charts:** Recharts
- **Real-time:** Socket.io client

## 🔐 Environment Variables

Key environment variables to configure in `server/.env`:

```env
# Database
DB_HOST=localhost
DB_PORT=5432
DB_NAME=lunara_db
DB_USER=postgres
DB_PASSWORD=your_password

# JWT
JWT_SECRET=your_jwt_secret
JWT_EXPIRES_IN=7d

# Razorpay
RAZORPAY_KEY_ID=your_key_id
RAZORPAY_KEY_SECRET=your_key_secret

# Email
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your_email@gmail.com
SMTP_PASSWORD=your_app_password
```

See `.env.example` for complete list of variables.

## 📝 Next Steps

After completing Phase 1 setup:

1. **Phase 2:** Database Schema & Models
   - Design and implement database schema
   - Create Sequelize models for all entities
   - Set up migrations and seeders

2. **Phase 3:** Core API Development
   - Authentication & authorization
   - User management endpoints
   - Venue management APIs
   - Booking & payment endpoints

3. **Phase 4:** Admin Panel Development
   - Dashboard interface
   - User & venue management UI
   - Analytics visualizations
   - Compliance tools

## 🛡️ Security & Compliance

This platform includes regulatory compliance features:
- DPDP Act 2023 compliance (data protection)
- Age verification system
- Content moderation tools
- Audit logging
- Escrow account integration support

## 📄 License

Private - All rights reserved

## 👥 Support

For issues or questions, please contact the development team.

---

**Status:** Phase 1 Complete ✅
**Next:** Phase 2 - Database Implementation
