import dotenv from 'dotenv';
import sequelize from './config/database';
import fs from 'fs';

dotenv.config();

const logFile = 'db-init-log.txt';
let logOutput = '';

function log(message: string) {
  console.log(message);
  logOutput += message + '\n';
}

async function initializeDatabase() {
  try {
    log('='.repeat(70));
    log('Lunara Database Initialization - Enhanced Schema');
    log('='.repeat(70));
    log('');

    log('Step 1: Testing database connection...');
    await sequelize.authenticate();
    log('✅ Database connected successfully');
    log('');

    log('Step 2: Creating tables...');
    log('');

    // Core tables
    log('Creating core tables...');

    // Users table
    await sequelize.query(`
      CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        email VARCHAR(255) UNIQUE NOT NULL,
        phone VARCHAR(20) UNIQUE NOT NULL,
        password_hash VARCHAR(255) NOT NULL,
        first_name VARCHAR(100) NOT NULL,
        last_name VARCHAR(100) NOT NULL,
        date_of_birth DATE NOT NULL,
        role VARCHAR(20) NOT NULL DEFAULT 'customer',
        is_verified BOOLEAN DEFAULT FALSE,
        is_active BOOLEAN DEFAULT TRUE,
        profile_image_url VARCHAR(500),
        email_verified_at TIMESTAMP,
        phone_verified_at TIMESTAMP,
        onboarding_completed BOOLEAN DEFAULT FALSE,
        last_login_at TIMESTAMP,
        is_online BOOLEAN DEFAULT FALSE,
        last_active_at TIMESTAMP,
        block_count INTEGER DEFAULT 0,
        is_autoblocked BOOLEAN DEFAULT FALSE,
        autoblocked_reason TEXT,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
    `);
    log('✅ users');

    // Venues table
    await sequelize.query(`
      CREATE TABLE IF NOT EXISTS venues (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        owner_id UUID NOT NULL REFERENCES users(id),
        name VARCHAR(255) NOT NULL,
        slug VARCHAR(255) UNIQUE NOT NULL,
        description TEXT,
        category VARCHAR(20) NOT NULL,
        address_line1 VARCHAR(255) NOT NULL,
        address_line2 VARCHAR(255),
        city VARCHAR(100) NOT NULL,
        state VARCHAR(100) NOT NULL,
        postal_code VARCHAR(10) NOT NULL,
        latitude DECIMAL(10,8),
        longitude DECIMAL(11,8),
        phone VARCHAR(20) NOT NULL,
        email VARCHAR(255),
        capacity INTEGER NOT NULL,
        opening_time TIME,
        closing_time TIME,
        average_rating DECIMAL(3,2) DEFAULT 0,
        total_reviews INTEGER DEFAULT 0,
        status VARCHAR(20) DEFAULT 'pending',
        featured BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
    `);
    log('✅ venues');

    // Bookings table
    await sequelize.query(`
      CREATE TABLE IF NOT EXISTS bookings (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        booking_number VARCHAR(20) UNIQUE NOT NULL,
        user_id UUID NOT NULL REFERENCES users(id),
        venue_id UUID NOT NULL REFERENCES venues(id),
        booking_date DATE NOT NULL,
        start_time TIME NOT NULL,
        end_time TIME,
        number_of_guests INTEGER NOT NULL,
        total_amount DECIMAL(10,2) NOT NULL,
        deposit_amount DECIMAL(10,2) DEFAULT 0,
        commission_amount DECIMAL(10,2) NOT NULL,
        status VARCHAR(20) DEFAULT 'pending',
        payment_status VARCHAR(20) DEFAULT 'pending',
        is_group_booking BOOLEAN DEFAULT FALSE,
        cancellation_reason TEXT,
        cancelled_at TIMESTAMP,
        special_requests TEXT,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
    `);
    log('✅ bookings');

    // Group Bookings table
    await sequelize.query(`
      CREATE TABLE IF NOT EXISTS group_bookings (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        booking_id UUID NOT NULL REFERENCES bookings(id),
        organizer_id UUID NOT NULL REFERENCES users(id),
        group_name VARCHAR(100),
        split_payment_enabled BOOLEAN DEFAULT TRUE,
        split_type VARCHAR(20) DEFAULT 'equal',
        total_members INTEGER NOT NULL,
        confirmed_members INTEGER DEFAULT 0,
        paid_members INTEGER DEFAULT 0,
        invitation_code VARCHAR(20) UNIQUE NOT NULL,
        invitation_expires_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
    `);
    log('✅ group_bookings');

    // Payments table
    await sequelize.query(`
      CREATE TABLE IF NOT EXISTS payments (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        transaction_id VARCHAR(100) UNIQUE NOT NULL,
        booking_id UUID NOT NULL REFERENCES bookings(id),
        user_id UUID NOT NULL REFERENCES users(id),
        group_member_id UUID,
        amount DECIMAL(10,2) NOT NULL,
        currency VARCHAR(3) DEFAULT 'INR',
        payment_method VARCHAR(20) NOT NULL,
        payment_gateway VARCHAR(50) DEFAULT 'razorpay',
        gateway_response JSONB,
        status VARCHAR(20) DEFAULT 'initiated',
        failure_reason TEXT,
        refund_amount DECIMAL(10,2) DEFAULT 0,
        refunded_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
    `);
    log('✅ payments');

    log('');
    log('Creating authentication tables...');

    // Password Reset Tokens
    await sequelize.query(`
      CREATE TABLE IF NOT EXISTS password_reset_tokens (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        token VARCHAR(255) NOT NULL UNIQUE,
        expires_at TIMESTAMP NOT NULL,
        used_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);
    log('✅ password_reset_tokens');

    // Email Verifications
    await sequelize.query(`
      CREATE TABLE IF NOT EXISTS email_verifications (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        token VARCHAR(255) NOT NULL UNIQUE,
        verified_at TIMESTAMP,
        expires_at TIMESTAMP NOT NULL,
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);
    log('✅ email_verifications');

    // OTP Verifications
    await sequelize.query(`
      CREATE TABLE IF NOT EXISTS otp_verifications (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        phone VARCHAR(20) NOT NULL,
        otp_code VARCHAR(255) NOT NULL,
        purpose VARCHAR(20) NOT NULL,
        verified_at TIMESTAMP,
        expires_at TIMESTAMP NOT NULL,
        attempts INTEGER DEFAULT 0,
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);
    log('✅ otp_verifications');

    log('');
    log('Creating user profile tables...');

    // User Profiles
    await sequelize.query(`
      CREATE TABLE IF NOT EXISTS user_profiles (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
        display_name VARCHAR(100),
        bio TEXT,
        gender VARCHAR(20),
        city VARCHAR(100),
        occupation VARCHAR(100),
        company VARCHAR(100),
        education VARCHAR(200),
        relationship_status VARCHAR(20),
        looking_for TEXT[],
        interests TEXT[],
        instagram_handle VARCHAR(50),
        spotify_profile VARCHAR(255),
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
    `);
    log('✅ user_profiles');

    // User Photos
    await sequelize.query(`
      CREATE TABLE IF NOT EXISTS user_photos (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        file_path VARCHAR(500) NOT NULL,
        file_size INTEGER NOT NULL,
        mime_type VARCHAR(50) NOT NULL,
        is_primary BOOLEAN DEFAULT FALSE,
        display_order INTEGER DEFAULT 0,
        uploaded_at TIMESTAMP DEFAULT NOW(),
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);
    log('✅ user_photos');

    // User Interests
    await sequelize.query(`
      CREATE TABLE IF NOT EXISTS user_interests (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        category VARCHAR(50) NOT NULL,
        interest VARCHAR(100) NOT NULL,
        proficiency_level VARCHAR(20),
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);
    log('✅ user_interests');

    // User Preferences
    await sequelize.query(`
      CREATE TABLE IF NOT EXISTS user_preferences (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
        preferred_venues TEXT[],
        preferred_crowd_size VARCHAR(20),
        music_preference TEXT[],
        drink_preference TEXT[],
        budget_range VARCHAR(20),
        party_time_preference VARCHAR(20),
        group_size_preference VARCHAR(20),
        match_distance_km INTEGER DEFAULT 10,
        show_me_in_matching BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
    `);
    log('✅ user_preferences');

    log('');
    log('Creating social matching tables...');

    // User Matches
    await sequelize.query(`
      CREATE TABLE IF NOT EXISTS user_matches (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user1_id UUID NOT NULL REFERENCES users(id),
        user2_id UUID NOT NULL REFERENCES users(id),
        compatibility_score DECIMAL(5,2) NOT NULL,
        common_interests JSONB,
        match_reason TEXT,
        status VARCHAR(20) DEFAULT 'pending',
        venue_id UUID REFERENCES venues(id),
        event_date DATE,
        expires_at TIMESTAMP NOT NULL,
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);
    log('✅ user_matches');

    // Social Connections
    await sequelize.query(`
      CREATE TABLE IF NOT EXISTS social_connections (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        requester_id UUID NOT NULL REFERENCES users(id),
        receiver_id UUID NOT NULL REFERENCES users(id),
        status VARCHAR(20) DEFAULT 'pending',
        connected_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);
    log('✅ social_connections');

    log('');
    log('Creating venue media tables...');

    // Venue Images
    await sequelize.query(`
      CREATE TABLE IF NOT EXISTS venue_images (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        venue_id UUID NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
        file_path VARCHAR(500) NOT NULL,
        file_size INTEGER NOT NULL,
        mime_type VARCHAR(50) NOT NULL,
        image_type VARCHAR(20) NOT NULL,
        caption VARCHAR(255),
        is_primary BOOLEAN DEFAULT FALSE,
        display_order INTEGER DEFAULT 0,
        uploaded_by UUID NOT NULL REFERENCES users(id),
        uploaded_at TIMESTAMP DEFAULT NOW(),
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);
    log('✅ venue_images');

    log('');
    log('Step 3: Verifying tables...');
    const [results]: any = await sequelize.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      AND table_type = 'BASE TABLE'
      ORDER BY table_name;
    `);

    log(`Tables in database (${results.length}):`);
    results.forEach((row: any) => {
      log(`  ✓ ${row.table_name}`);
    });
    log('');

    log('='.repeat(70));
    log('✅ Database initialization completed successfully!');
    log('='.repeat(70));
    log('');
    log(`Total tables created: ${results.length}`);
    log('');
    log('New features enabled:');
    log('  ✅ Password reset workflow');
    log('  ✅ Email verification');
    log('  ✅ OTP phone verification');
    log('  ✅ Extended user profiles');
    log('  ✅ User photo galleries');
    log('  ✅ Interest-based matching');
    log('  ✅ Vibe matching preferences');
    log('  ✅ Social connections');
    log('  ✅ Venue photo management');
    log('');

    fs.writeFileSync(logFile, logOutput);
    await sequelize.close();
    process.exit(0);
  } catch (error: any) {
    log('');
    log('='.repeat(70));
    log('❌ Database initialization failed!');
    log('='.repeat(70));
    log(`Error: ${error.message}`);
    if (error.stack) {
      log(`Stack: ${error.stack}`);
    }

    fs.writeFileSync(logFile, logOutput);
    process.exit(1);
  }
}

initializeDatabase();
