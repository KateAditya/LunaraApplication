# Lunara Database Schema Design

## Overview

Comprehensive database schema for the Lunara/NightVenue platform - a B2B2C nightlife booking and management system.

---

## Core Entities

### 1. Users & Authentication

#### `users`
Primary user accounts table for customers, venue owners, and administrators.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PRIMARY KEY | Unique user identifier |
| email | VARCHAR(255) | UNIQUE, NOT NULL | User email address |
| phone | VARCHAR(20) | UNIQUE, NOT NULL | Phone number (Indian format) |
| password_hash | VARCHAR(255) | NOT NULL | Bcrypt hashed password |
| first_name | VARCHAR(100) | NOT NULL | First name |
| last_name | VARCHAR(100) | NOT NULL | Last name |
| date_of_birth | DATE | NOT NULL | Date of birth (age verification) |
| role | ENUM | NOT NULL, DEFAULT 'customer' | Role: customer, venue_owner, admin |
| is_verified | BOOLEAN | DEFAULT false | Email/phone verification status |
| is_active | BOOLEAN | DEFAULT true | Account active status |
| profile_image_url | VARCHAR(500) | | Profile picture URL |
| created_at | TIMESTAMP | DEFAULT NOW() | Account creation timestamp |
| updated_at | TIMESTAMP | DEFAULT NOW() | Last update timestamp |
| last_login_at | TIMESTAMP | | Last login timestamp |

**Indexes:**
- `idx_users_email` on `email`
- `idx_users_phone` on `phone`
- `idx_users_role` on `role`

---

### 2. Venues

#### `venues`
Nightlife venues (pubs, clubs, hotels, lounges).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PRIMARY KEY | Unique venue identifier |
| owner_id | UUID | FOREIGN KEY → users(id) | Venue owner reference |
| name | VARCHAR(255) | NOT NULL | Venue name |
| slug | VARCHAR(255) | UNIQUE, NOT NULL | URL-friendly identifier |
| description | TEXT | | Venue description |
| category | ENUM | NOT NULL | pub, club, hotel, lounge |
| address_line1 | VARCHAR(255) | NOT NULL | Street address |
| address_line2 | VARCHAR(255) | | Additional address |
| city | VARCHAR(100) | NOT NULL | City name |
| state | VARCHAR(100) | NOT NULL | State name |
| postal_code | VARCHAR(10) | NOT NULL | PIN code |
| latitude | DECIMAL(10,8) | | GPS latitude |
| longitude | DECIMAL(11,8) | | GPS longitude |
| phone | VARCHAR(20) | NOT NULL | Contact number |
| email | VARCHAR(255) | | Contact email |
| capacity | INTEGER | NOT NULL | Total capacity |
| opening_time | TIME | | Opening time |
| closing_time | TIME | | Closing time |
| average_rating | DECIMAL(3,2) | DEFAULT 0 | Average review rating (0-5) |
| total_reviews | INTEGER | DEFAULT 0 | Total number of reviews |
| status | ENUM | DEFAULT 'pending' | pending, approved, rejected, suspended |
| featured | BOOLEAN | DEFAULT false | Featured venue flag |
| created_at | TIMESTAMP | DEFAULT NOW() | |
| updated_at | TIMESTAMP | DEFAULT NOW() | |

**Indexes:**
- `idx_venues_owner` on `owner_id`
- `idx_venues_city` on `city`
- `idx_venues_category` on `category`
- `idx_venues_status` on `status`
- `idx_venues_location` on `(latitude, longitude)`

---

#### `venue_licenses`
Alcohol licensing and compliance tracking.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PRIMARY KEY | |
| venue_id | UUID | FOREIGN KEY → venues(id) | |
| license_type | VARCHAR(50) | NOT NULL | L-6, L-17, L-18, etc. |
| license_number | VARCHAR(100) | NOT NULL | License number |
| issuing_authority | VARCHAR(255) | NOT NULL | State Excise Dept, etc. |
| issue_date | DATE | NOT NULL | Issue date |
| expiry_date | DATE | NOT NULL | Expiry date |
| document_url | VARCHAR(500) | | Uploaded license document |
| status | ENUM | DEFAULT 'pending' | pending, verified, expired, rejected |
| verified_by | UUID | FOREIGN KEY → users(id) | Admin who verified |
| verified_at | TIMESTAMP | | Verification timestamp |
| created_at | TIMESTAMP | DEFAULT NOW() | |
| updated_at | TIMESTAMP | DEFAULT NOW() | |

---

#### `venue_images`
Venue photo gallery.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PRIMARY KEY | |
| venue_id | UUID | FOREIGN KEY → venues(id) | |
| image_url | VARCHAR(500) | NOT NULL | Image URL |
| caption | VARCHAR(255) | | Image caption |
| is_primary | BOOLEAN | DEFAULT false | Primary/cover photo |
| display_order | INTEGER | DEFAULT 0 | Display order |
| created_at | TIMESTAMP | DEFAULT NOW() | |

---

#### `venue_availability`
Real-time table/seat availability tracking.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PRIMARY KEY | |
| venue_id | UUID | FOREIGN KEY → venues(id) | |
| date | DATE | NOT NULL | Availability date |
| time_slot | TIME | NOT NULL | Time slot (e.g., 20:00) |
| available_capacity | INTEGER | NOT NULL | Available seats/tables |
| total_capacity | INTEGER | NOT NULL | Total capacity for slot |
| price_per_person | DECIMAL(10,2) | | Dynamic pricing per person |
| created_at | TIMESTAMP | DEFAULT NOW() | |
| updated_at | TIMESTAMP | DEFAULT NOW() | |

**Indexes:**
- `idx_venue_availability_venue_date` on `(venue_id, date)`
- `idx_venue_availability_date` on `date`

---

### 3. Bookings

#### `bookings`
Individual and group reservations.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PRIMARY KEY | Booking reference |
| booking_number | VARCHAR(20) | UNIQUE, NOT NULL | Human-readable booking ID |
| user_id | UUID | FOREIGN KEY → users(id) | Customer who booked |
| venue_id | UUID | FOREIGN KEY → venues(id) | Venue reference |
| booking_date | DATE | NOT NULL | Reservation date |
| start_time | TIME | NOT NULL | Start time |
| end_time | TIME | | Expected end time |
| number_of_guests | INTEGER | NOT NULL | Total guests |
| total_amount | DECIMAL(10,2) | NOT NULL | Total booking amount |
| deposit_amount | DECIMAL(10,2) | DEFAULT 0 | Advance deposit |
| commission_amount | DECIMAL(10,2) | NOT NULL | Platform commission |
| status | ENUM | DEFAULT 'pending' | pending, confirmed, cancelled, completed, no_show |
| payment_status | ENUM | DEFAULT 'pending' | pending, paid, partially_paid, refunded |
| is_group_booking | BOOLEAN | DEFAULT false | Group booking flag |
| cancellation_reason | TEXT | | Reason for cancellation |
| cancelled_at | TIMESTAMP | | Cancellation timestamp |
| special_requests | TEXT | | Customer special requests |
| created_at | TIMESTAMP | DEFAULT NOW() | |
| updated_at | TIMESTAMP | DEFAULT NOW() | |

**Indexes:**
- `idx_bookings_user` on `user_id`
- `idx_bookings_venue` on `venue_id`
- `idx_bookings_date` on `booking_date`
- `idx_bookings_status` on `status`
- `idx_bookings_number` on `booking_number`

---

#### `group_bookings`
Group booking metadata and coordination.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PRIMARY KEY | |
| booking_id | UUID | FOREIGN KEY → bookings(id) | Primary booking reference |
| organizer_id | UUID | FOREIGN KEY → users(id) | Group organizer |
| group_name | VARCHAR(100) | | Group name/title |
| split_payment_enabled | BOOLEAN | DEFAULT true | Enable split payments |
| split_type | ENUM | DEFAULT 'equal' | equal, custom, percentage |
| total_members | INTEGER | NOT NULL | Total group members |
| confirmed_members | INTEGER | DEFAULT 0 | Members who confirmed |
| paid_members | INTEGER | DEFAULT 0 | Members who paid |
| invitation_code | VARCHAR(20) | UNIQUE | Unique invitation code |
| invitation_expires_at | TIMESTAMP | | Invitation expiry |
| created_at | TIMESTAMP | DEFAULT NOW() | |
| updated_at | TIMESTAMP | DEFAULT NOW() | |

---

#### `group_members`
Individual members of group bookings.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PRIMARY KEY | |
| group_booking_id | UUID | FOREIGN KEY → group_bookings(id) | |
| user_id | UUID | FOREIGN KEY → users(id) | Member user |
| member_name | VARCHAR(100) | NOT NULL | Member name |
| member_email | VARCHAR(255) | | Member email |
| member_phone | VARCHAR(20) | | Member phone |
| share_amount | DECIMAL(10,2) | NOT NULL | Member's share |
| payment_status | ENUM | DEFAULT 'pending' | pending, paid, refunded |
| confirmed_attendance | BOOLEAN | DEFAULT false | RSVP confirmation |
| joined_at | TIMESTAMP | DEFAULT NOW() | When member joined |
| paid_at | TIMESTAMP | | Payment timestamp |

---

### 4. Payments

#### `payments`
Payment transaction records.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PRIMARY KEY | |
| transaction_id | VARCHAR(100) | UNIQUE, NOT NULL | Payment gateway transaction ID |
| booking_id | UUID | FOREIGN KEY → bookings(id) | |
| user_id | UUID | FOREIGN KEY → users(id) | Payer |
| group_member_id | UUID | FOREIGN KEY → group_members(id) | For split payments |
| amount | DECIMAL(10,2) | NOT NULL | Payment amount |
| currency | VARCHAR(3) | DEFAULT 'INR' | Currency code |
| payment_method | ENUM | NOT NULL | razorpay, upi, card, wallet |
| payment_gateway | VARCHAR(50) | DEFAULT 'razorpay' | Gateway used |
| gateway_response | JSONB | | Full gateway response |
| status | ENUM | DEFAULT 'initiated' | initiated, processing, successful, failed, refunded |
| failure_reason | TEXT | | Failure reason if failed |
| refund_amount | DECIMAL(10,2) | DEFAULT 0 | Refunded amount |
| refunded_at | TIMESTAMP | | Refund timestamp |
| created_at | TIMESTAMP | DEFAULT NOW() | |
| updated_at | TIMESTAMP | DEFAULT NOW() | |

**Indexes:**
- `idx_payments_booking` on `booking_id`
- `idx_payments_user` on `user_id`
- `idx_payments_transaction` on `transaction_id`
- `idx_payments_status` on `status`

---

#### `escrow_transactions`
Escrow account tracking for compliance.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PRIMARY KEY | |
| payment_id | UUID | FOREIGN KEY → payments(id) | |
| booking_id | UUID | FOREIGN KEY → bookings(id) | |
| amount | DECIMAL(10,2) | NOT NULL | Held amount |
| status | ENUM | DEFAULT 'held' | held, released, refunded |
| held_at | TIMESTAMP | DEFAULT NOW() | When funds held |
| released_at | TIMESTAMP | | When released to venue |
| release_scheduled_for | TIMESTAMP | | Scheduled release (T+2) |
| venue_payout_id | VARCHAR(100) | | Payout transaction ID |
| created_at | TIMESTAMP | DEFAULT NOW() | |

---

### 5. Reviews & Ratings

#### `reviews`
Venue reviews from customers.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PRIMARY KEY | |
| booking_id | UUID | FOREIGN KEY → bookings(id) | Associated booking |
| user_id | UUID | FOREIGN KEY → users(id) | Reviewer |
| venue_id | UUID | FOREIGN KEY → venues(id) | Reviewed venue |
| rating | INTEGER | NOT NULL, CHECK (1-5) | Star rating (1-5) |
| title | VARCHAR(200) | | Review title |
| comment | TEXT | | Review text |
| ambience_rating | INTEGER | CHECK (1-5) | Specific ratings |
| service_rating | INTEGER | CHECK (1-5) | |
| food_rating | INTEGER | CHECK (1-5) | |
| value_rating | INTEGER | CHECK (1-5) | |
| is_verified | BOOLEAN | DEFAULT false | Verified booking review |
| status | ENUM | DEFAULT 'pending' | pending, approved, rejected, flagged |
| moderated_by | UUID | FOREIGN KEY → users(id) | Moderator |
| moderated_at | TIMESTAMP | | Moderation timestamp |
| created_at | TIMESTAMP | DEFAULT NOW() | |
| updated_at | TIMESTAMP | DEFAULT NOW() | |

---

### 6. Loyalty & Gamification

#### `loyalty_points`
Multi-venue loyalty program.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PRIMARY KEY | |
| user_id | UUID | FOREIGN KEY → users(id) | |
| booking_id | UUID | FOREIGN KEY → bookings(id) | Earning source |
| points | INTEGER | NOT NULL | Points earned/spent |
| transaction_type | ENUM | NOT NULL | earned, redeemed, expired |
| description | VARCHAR(255) | | Transaction description |
| expires_at | TIMESTAMP | | Points expiry |
| created_at | TIMESTAMP | DEFAULT NOW() | |

---

### 7. Compliance & Audit

#### `audit_logs`
Comprehensive audit trail for compliance (DPDP Act).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PRIMARY KEY | |
| user_id | UUID | FOREIGN KEY → users(id) | Actor |
| action | VARCHAR(100) | NOT NULL | Action performed |
| entity_type | VARCHAR(50) | NOT NULL | Table/entity affected |
| entity_id | UUID | | Affected record ID |
| old_values | JSONB | | Previous values |
| new_values | JSONB | | New values |
| ip_address | VARCHAR(45) | | IPv4/IPv6 address |
| user_agent | TEXT | | Browser/client info |
| created_at | TIMESTAMP | DEFAULT NOW() | |

---

#### `grievances`
User complaints and resolution tracking.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PRIMARY KEY | |
| ticket_number | VARCHAR(20) | UNIQUE, NOT NULL | Support ticket number |
| user_id | UUID | FOREIGN KEY → users(id) | Complainant |
| booking_id | UUID | FOREIGN KEY → bookings(id) | Related booking |
| category | ENUM | NOT NULL | booking, payment, venue, service, other |
| subject | VARCHAR(255) | NOT NULL | Grievance subject |
| description | TEXT | NOT NULL | Detailed description |
| priority | ENUM | DEFAULT 'medium' | low, medium, high, critical |
| status | ENUM | DEFAULT 'open' | open, in_progress, resolved, closed |
| assigned_to | UUID | FOREIGN KEY → users(id) | Grievance Officer |
| resolution | TEXT | | Resolution details |
| resolved_at | TIMESTAMP | | Resolution timestamp |
| created_at | TIMESTAMP | DEFAULT NOW() | |
| updated_at | TIMESTAMP | DEFAULT NOW() | |

---

## Relationships Summary

```
users (1) ----< (N) venues [owner_id]
users (1) ----< (N) bookings [user_id]
users (1) ----< (N) reviews [user_id]
users (1) ----< (N) payments [user_id]

venues (1) ----< (N) venue_licenses
venues (1) ----< (N) venue_images
venues (1) ----< (N) venue_availability
venues (1) ----< (N) bookings [venue_id]
venues (1) ----< (N) reviews [venue_id]

bookings (1) ---- (0-1) group_bookings
bookings (1) ----< (N) payments
bookings (1) ---- (0-1) reviews

group_bookings (1) ----< (N) group_members

payments (1) ---- (0-1) escrow_transactions
```

---

## Performance Considerations

### Indexes Created
- All foreign keys have indexes
- Frequently queried fields (email, phone, booking_date, status)
- Composite indexes for common query patterns
- Geospatial index for venue location searches

### Data Types
- UUID for all primary keys (better for distributed systems)
- ENUM for status fields (data integrity)
- JSONB for flexible schema fields (gateway responses, audit logs)
- DECIMAL for monetary values (precision)
- TIMESTAMP for all datetime fields (timezone support)

---

## Next Steps

1. Create Sequelize models based on this schema
2. Implement database migrations
3. Add model validations and hooks
4. Create seed data for testing
5. Set up model associations/relationships

