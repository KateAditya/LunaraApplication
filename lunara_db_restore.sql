--
-- PostgreSQL database dump
--

\restrict hAgO9zQwPk1ovVr7vyriW7GDwcouSuxyOSEJrkLLN0moHAa8RtnpSwGGpxR1Zr8

-- Dumped from database version 18.1
-- Dumped by pg_dump version 18.0

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: enum_SubscriptionPackages_tier; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public."enum_SubscriptionPackages_tier" AS ENUM (
    'FREE',
    'CORE',
    'PLUS',
    'PRO',
    'ELITE'
);


--
-- Name: enum_UserSubscriptions_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public."enum_UserSubscriptions_status" AS ENUM (
    'ACTIVE',
    'EXPIRED',
    'CANCELLED'
);


--
-- Name: enum_ads_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_ads_type AS ENUM (
    'Ads',
    'Party'
);


--
-- Name: enum_booking_members_payment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_booking_members_payment_status AS ENUM (
    'pending',
    'paid'
);


--
-- Name: enum_booking_table_packages_name; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_booking_table_packages_name AS ENUM (
    'silver',
    'gold',
    'platinum'
);


--
-- Name: enum_bookings_admin_approval_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_bookings_admin_approval_status AS ENUM (
    'pending',
    'approved',
    'rejected',
    'payment_sent',
    'payment_done'
);


--
-- Name: enum_bookings_going_mode; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_bookings_going_mode AS ENUM (
    'solo',
    'plan',
    'party_request'
);


--
-- Name: enum_bookings_payment_mode; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_bookings_payment_mode AS ENUM (
    'pay_now',
    'split_bill'
);


--
-- Name: enum_bookings_payment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_bookings_payment_status AS ENUM (
    'pending',
    'paid',
    'partially_paid',
    'refunded'
);


--
-- Name: enum_bookings_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_bookings_status AS ENUM (
    'pending',
    'confirmed',
    'cancelled',
    'completed',
    'no_show'
);


--
-- Name: enum_chat_subscriptions_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_chat_subscriptions_status AS ENUM (
    'active',
    'expired'
);


--
-- Name: enum_chat_subscriptions_subscription_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_chat_subscriptions_subscription_type AS ENUM (
    'free',
    'paid',
    'pay_req'
);


--
-- Name: enum_conversations_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_conversations_status AS ENUM (
    'active',
    'archived',
    'blocked'
);


--
-- Name: enum_group_bookings_split_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_group_bookings_split_type AS ENUM (
    'equal',
    'custom',
    'percentage'
);


--
-- Name: enum_group_parties_payment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_group_parties_payment_status AS ENUM (
    'pending',
    'paid',
    'failed'
);


--
-- Name: enum_group_parties_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_group_parties_status AS ENUM (
    'pending',
    'confirmed',
    'cancelled'
);


--
-- Name: enum_messages_invitation_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_messages_invitation_status AS ENUM (
    'pending',
    'accepted',
    'declined'
);


--
-- Name: enum_messages_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_messages_status AS ENUM (
    'sent',
    'delivered',
    'read'
);


--
-- Name: enum_messages_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_messages_type AS ENUM (
    'text',
    'image',
    'sticker',
    'invitation',
    'icebreaker'
);


--
-- Name: enum_otp_verifications_purpose; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_otp_verifications_purpose AS ENUM (
    'registration',
    'login',
    'verification',
    'password_reset'
);


--
-- Name: enum_party_plan_requests_joiner_payment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_party_plan_requests_joiner_payment_status AS ENUM (
    'unpaid',
    'paid',
    'refunded'
);


--
-- Name: enum_party_plan_requests_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_party_plan_requests_status AS ENUM (
    'pending',
    'payment_pending',
    'accepted',
    'rejected',
    'cancelled',
    'payment_failed'
);


--
-- Name: enum_party_plans_host_payment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_party_plans_host_payment_status AS ENUM (
    'unpaid',
    'paid',
    'refunded'
);


--
-- Name: enum_party_plans_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_party_plans_status AS ENUM (
    'active',
    'inactive',
    'cancelled'
);


--
-- Name: enum_party_plans_visibility; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_party_plans_visibility AS ENUM (
    'public',
    'private',
    'both'
);


--
-- Name: enum_payments_payment_method; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_payments_payment_method AS ENUM (
    'razorpay',
    'upi',
    'card',
    'wallet'
);


--
-- Name: enum_payments_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_payments_status AS ENUM (
    'initiated',
    'processing',
    'successful',
    'failed',
    'refunded'
);


--
-- Name: enum_plan_join_requests_payment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_plan_join_requests_payment_status AS ENUM (
    'pending',
    'paid'
);


--
-- Name: enum_plan_join_requests_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_plan_join_requests_status AS ENUM (
    'pending',
    'accepted',
    'rejected',
    'cancelled'
);


--
-- Name: enum_plans_payment_option; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_plans_payment_option AS ENUM (
    'full',
    'split'
);


--
-- Name: enum_plans_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_plans_status AS ENUM (
    'active',
    'full',
    'secured',
    'cancelled'
);


--
-- Name: enum_social_connections_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_social_connections_status AS ENUM (
    'pending',
    'accepted',
    'rejected',
    'blocked'
);


--
-- Name: enum_strangers_meet_joiners_payment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_strangers_meet_joiners_payment_status AS ENUM (
    'pending',
    'paid'
);


--
-- Name: enum_strangers_meet_requests_payment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_strangers_meet_requests_payment_status AS ENUM (
    'unpaid',
    'paid'
);


--
-- Name: enum_strangers_meet_requests_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_strangers_meet_requests_status AS ENUM (
    'pending',
    'approved',
    'rejected',
    'completed'
);


--
-- Name: enum_user_matches_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_user_matches_status AS ENUM (
    'pending',
    'connected',
    'declined',
    'expired'
);


--
-- Name: enum_users_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_users_role AS ENUM (
    'customer',
    'venue_owner',
    'admin'
);


--
-- Name: enum_venue_images_image_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_venue_images_image_type AS ENUM (
    'cover',
    'interior',
    'exterior',
    'menu',
    'party_packages',
    'event',
    'video',
    'food_menu',
    'bar_menu',
    'beverage_menu'
);


--
-- Name: enum_venues_category; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_venues_category AS ENUM (
    'pub',
    'club',
    'hotel',
    'lounge',
    'bar',
    'cafe',
    'restaurant',
    'rooftop'
);


--
-- Name: enum_venues_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.enum_venues_status AS ENUM (
    'pending',
    'approved',
    'rejected',
    'suspended'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: SubscriptionPackages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."SubscriptionPackages" (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    tier public."enum_SubscriptionPackages_tier" DEFAULT 'FREE'::public."enum_SubscriptionPackages_tier" NOT NULL,
    price numeric(10,2) DEFAULT 0 NOT NULL,
    duration_days integer DEFAULT 0 NOT NULL,
    daily_match_requests integer DEFAULT 3 NOT NULL,
    daily_likes integer DEFAULT 7 NOT NULL,
    daily_posts integer DEFAULT 5 NOT NULL,
    superlikes_per_cycle integer DEFAULT 0 NOT NULL,
    boosts_per_cycle integer DEFAULT 0 NOT NULL,
    has_hide_profile boolean DEFAULT false NOT NULL,
    has_priority_visibility boolean DEFAULT false NOT NULL,
    has_trust_badge boolean DEFAULT false NOT NULL,
    has_elite_badge boolean DEFAULT false NOT NULL,
    can_see_who_liked boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: UserSubscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."UserSubscriptions" (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    package_id uuid NOT NULL,
    status public."enum_UserSubscriptions_status" DEFAULT 'ACTIVE'::public."enum_UserSubscriptions_status" NOT NULL,
    start_date timestamp with time zone NOT NULL,
    end_date timestamp with time zone NOT NULL,
    superlikes_remaining integer DEFAULT 0 NOT NULL,
    boosts_remaining integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: ads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ads (
    id uuid NOT NULL,
    type public.enum_ads_type DEFAULT 'Ads'::public.enum_ads_type NOT NULL,
    venue_id uuid,
    city character varying(255),
    area character varying(255),
    image_path character varying(255) NOT NULL,
    from_date timestamp with time zone NOT NULL,
    to_date timestamp with time zone NOT NULL,
    is_active boolean DEFAULT true,
    social_links jsonb DEFAULT '[]'::jsonb,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    about_event text,
    title character varying(255)
);


--
-- Name: booking_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.booking_members (
    id uuid NOT NULL,
    group_booking_id uuid NOT NULL,
    user_id uuid,
    display_name character varying(100) NOT NULL,
    share_amount numeric(10,2) NOT NULL,
    payment_status public.enum_booking_members_payment_status DEFAULT 'pending'::public.enum_booking_members_payment_status,
    paid_at timestamp with time zone,
    transaction_id character varying(100),
    is_organizer boolean DEFAULT false,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: booking_table_packages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.booking_table_packages (
    id uuid NOT NULL,
    venue_id uuid NOT NULL,
    name public.enum_booking_table_packages_name NOT NULL,
    label character varying(100) NOT NULL,
    description character varying(200) NOT NULL,
    price numeric(10,2) NOT NULL,
    max_guests integer NOT NULL,
    bottles_included integer DEFAULT 0,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: bookings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bookings (
    id uuid NOT NULL,
    booking_number character varying(20) NOT NULL,
    user_id uuid NOT NULL,
    venue_id uuid NOT NULL,
    booking_date date NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone,
    number_of_guests integer NOT NULL,
    total_amount numeric(10,2) NOT NULL,
    deposit_amount numeric(10,2) DEFAULT 0,
    commission_amount numeric(10,2) NOT NULL,
    status public.enum_bookings_status DEFAULT 'pending'::public.enum_bookings_status,
    payment_status public.enum_bookings_payment_status DEFAULT 'pending'::public.enum_bookings_payment_status,
    is_group_booking boolean DEFAULT false,
    cancellation_reason text,
    cancelled_at timestamp with time zone,
    special_requests text,
    going_mode public.enum_bookings_going_mode DEFAULT 'solo'::public.enum_bookings_going_mode,
    table_package character varying(20),
    payment_mode public.enum_bookings_payment_mode,
    ticket_code character varying(100),
    added_to_wallet boolean DEFAULT false,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    party_subject character varying(255),
    party_requirement character varying(255),
    party_description text,
    is_large_party_request boolean DEFAULT false,
    admin_approval_status public.enum_bookings_admin_approval_status,
    mobile_number character varying(20),
    optional_mobile_number character varying(20),
    admin_payment_link character varying(500),
    admin_payment_amount numeric(10,2)
);


--
-- Name: chat_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_subscriptions (
    id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    paid_by_id uuid NOT NULL,
    amount numeric(10,2) DEFAULT 0 NOT NULL,
    days_granted integer NOT NULL,
    valid_until timestamp with time zone NOT NULL,
    status public.enum_chat_subscriptions_status DEFAULT 'active'::public.enum_chat_subscriptions_status,
    subscription_type public.enum_chat_subscriptions_subscription_type DEFAULT 'free'::public.enum_chat_subscriptions_subscription_type,
    requested_by_id uuid,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: cities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cities (
    id uuid NOT NULL,
    name character varying(100) NOT NULL,
    state character varying(100),
    is_active boolean DEFAULT true,
    display_order integer DEFAULT 0,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: community_guidelines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.community_guidelines (
    id uuid NOT NULL,
    title character varying(255) NOT NULL,
    content text NOT NULL,
    category character varying(100) NOT NULL,
    is_active boolean DEFAULT true,
    display_order integer DEFAULT 0,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversations (
    id uuid NOT NULL,
    participant_one uuid NOT NULL,
    participant_two uuid NOT NULL,
    last_message_id uuid,
    last_message_at timestamp with time zone,
    last_message_preview character varying(200),
    unread_one integer DEFAULT 0,
    unread_two integer DEFAULT 0,
    status public.enum_conversations_status DEFAULT 'active'::public.enum_conversations_status,
    context_type character varying(20),
    context_id uuid,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: email_verifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_verifications (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    token character varying(255) NOT NULL,
    verified_at timestamp with time zone,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: group_bookings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.group_bookings (
    id uuid NOT NULL,
    booking_id uuid NOT NULL,
    organizer_id uuid NOT NULL,
    group_name character varying(100),
    split_payment_enabled boolean DEFAULT true,
    split_type public.enum_group_bookings_split_type DEFAULT 'equal'::public.enum_group_bookings_split_type,
    total_members integer NOT NULL,
    confirmed_members integer DEFAULT 0,
    paid_members integer DEFAULT 0,
    invitation_code character varying(20) NOT NULL,
    invitation_expires_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: group_parties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.group_parties (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    venue_id uuid NOT NULL,
    number_of_friends integer NOT NULL,
    table_booking_charge numeric(10,2) NOT NULL,
    discount_amount numeric(10,2) NOT NULL,
    total_amount numeric(10,2) NOT NULL,
    status public.enum_group_parties_status DEFAULT 'pending'::public.enum_group_parties_status NOT NULL,
    payment_status public.enum_group_parties_payment_status DEFAULT 'pending'::public.enum_group_parties_payment_status NOT NULL,
    payment_id character varying(100),
    party_date date NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    mobile_number character varying(255) NOT NULL,
    optional_mobile_number character varying(255)
);


--
-- Name: help_articles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.help_articles (
    id uuid NOT NULL,
    title character varying(255) NOT NULL,
    content text NOT NULL,
    category character varying(100) NOT NULL,
    is_published boolean DEFAULT false,
    display_order integer DEFAULT 0,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: legal_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.legal_documents (
    id uuid NOT NULL,
    title character varying(255) NOT NULL,
    type character varying(50) NOT NULL,
    content text NOT NULL,
    version character varying(20) NOT NULL,
    is_active boolean DEFAULT true,
    effective_date date NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    sender_id uuid NOT NULL,
    type public.enum_messages_type DEFAULT 'text'::public.enum_messages_type NOT NULL,
    content text,
    media_url text,
    media_mime_type character varying(50),
    invitation_ref uuid,
    invitation_ref_type character varying(20),
    invitation_time character varying(100),
    invitation_status public.enum_messages_invitation_status,
    status public.enum_messages_status DEFAULT 'sent'::public.enum_messages_status,
    read_at timestamp with time zone,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: otp_verifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.otp_verifications (
    id uuid NOT NULL,
    phone character varying(20) NOT NULL,
    otp_code character varying(255) NOT NULL,
    purpose public.enum_otp_verifications_purpose NOT NULL,
    verified_at timestamp with time zone,
    expires_at timestamp with time zone NOT NULL,
    attempts integer DEFAULT 0,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: party_plan_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.party_plan_requests (
    id uuid NOT NULL,
    plan_id uuid NOT NULL,
    requester_id uuid NOT NULL,
    status public.enum_party_plan_requests_status DEFAULT 'pending'::public.enum_party_plan_requests_status NOT NULL,
    joiner_payment_status public.enum_party_plan_requests_joiner_payment_status DEFAULT 'unpaid'::public.enum_party_plan_requests_joiner_payment_status NOT NULL,
    joiner_razorpay_order_id character varying(255),
    joiner_razorpay_payment_id character varying(255),
    payment_timeout_at timestamp with time zone,
    lat_lang_check_in boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: party_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.party_plans (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    venue_id uuid NOT NULL,
    message text NOT NULL,
    plan_date_time timestamp with time zone NOT NULL,
    status public.enum_party_plans_status DEFAULT 'active'::public.enum_party_plans_status NOT NULL,
    visibility public.enum_party_plans_visibility DEFAULT 'public'::public.enum_party_plans_visibility NOT NULL,
    selected_users uuid[],
    deposit_amount numeric(10,2) DEFAULT 99 NOT NULL,
    host_payment_status public.enum_party_plans_host_payment_status DEFAULT 'unpaid'::public.enum_party_plans_host_payment_status NOT NULL,
    host_razorpay_order_id character varying(255),
    host_razorpay_payment_id character varying(255),
    is_live boolean DEFAULT false,
    expires_at timestamp with time zone,
    host_lat_lang_check_in boolean DEFAULT false,
    payment_status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    mobile_number character varying(255) DEFAULT ''::character varying,
    optional_mobile_number character varying(255)
);


--
-- Name: password_reset_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.password_reset_tokens (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    token character varying(255) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    used_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id uuid NOT NULL,
    transaction_id character varying(100) NOT NULL,
    booking_id uuid NOT NULL,
    user_id uuid NOT NULL,
    group_member_id uuid,
    amount numeric(10,2) NOT NULL,
    currency character varying(3) DEFAULT 'INR'::character varying,
    payment_method public.enum_payments_payment_method NOT NULL,
    payment_gateway character varying(50) DEFAULT 'razorpay'::character varying,
    gateway_response jsonb,
    status public.enum_payments_status DEFAULT 'initiated'::public.enum_payments_status,
    failure_reason text,
    refund_amount numeric(10,2) DEFAULT 0,
    refunded_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: plan_join_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plan_join_requests (
    id uuid NOT NULL,
    plan_id uuid NOT NULL,
    requester_id uuid NOT NULL,
    status public.enum_plan_join_requests_status DEFAULT 'pending'::public.enum_plan_join_requests_status,
    payment_status public.enum_plan_join_requests_payment_status DEFAULT 'pending'::public.enum_plan_join_requests_payment_status,
    share_amount numeric(10,2) NOT NULL,
    transaction_id character varying(100),
    paid_at timestamp with time zone,
    message text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plans (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    venue_id uuid NOT NULL,
    plan_date date NOT NULL,
    start_time character varying(10) NOT NULL,
    table_package character varying(20) NOT NULL,
    payment_option public.enum_plans_payment_option NOT NULL,
    total_amount numeric(10,2) NOT NULL,
    max_joiners integer NOT NULL,
    current_joiners integer DEFAULT 0,
    status public.enum_plans_status DEFAULT 'active'::public.enum_plans_status,
    description text,
    booking_id uuid,
    host_payment_status character varying(20) DEFAULT 'pending'::character varying,
    host_transaction_id character varying(100),
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: social_connections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.social_connections (
    id uuid NOT NULL,
    requester_id uuid NOT NULL,
    receiver_id uuid NOT NULL,
    status public.enum_social_connections_status DEFAULT 'pending'::public.enum_social_connections_status,
    connected_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: strangers_meet_joiners; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.strangers_meet_joiners (
    id uuid NOT NULL,
    strangers_meet_request_id uuid NOT NULL,
    user_id uuid NOT NULL,
    payment_status public.enum_strangers_meet_joiners_payment_status DEFAULT 'pending'::public.enum_strangers_meet_joiners_payment_status NOT NULL,
    payment_amount numeric(10,2) DEFAULT 0 NOT NULL,
    razorpay_order_id character varying(100),
    razorpay_payment_id character varying(100),
    razorpay_signature character varying(200),
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: strangers_meet_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.strangers_meet_requests (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    venue_id uuid NOT NULL,
    subject character varying(200) NOT NULL,
    tagline text NOT NULL,
    event_date_time timestamp with time zone NOT NULL,
    number_of_persons integer NOT NULL,
    status public.enum_strangers_meet_requests_status DEFAULT 'pending'::public.enum_strangers_meet_requests_status NOT NULL,
    payment_amount numeric(10,2),
    payment_status public.enum_strangers_meet_requests_payment_status DEFAULT 'unpaid'::public.enum_strangers_meet_requests_payment_status NOT NULL,
    admin_notes text,
    ticket_id character varying(50),
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    razorpay_order_id character varying(100),
    razorpay_payment_id character varying(100),
    razorpay_signature character varying(200),
    mobile_number character varying(20) DEFAULT ''::character varying NOT NULL,
    alternate_mobile_number character varying(20),
    charges_per_head numeric(10,2) DEFAULT 0 NOT NULL,
    slots_filled integer DEFAULT 0 NOT NULL
);


--
-- Name: user_interests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_interests (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    category character varying(50) NOT NULL,
    interest character varying(100) NOT NULL,
    proficiency_level character varying(20),
    created_at timestamp with time zone NOT NULL
);


--
-- Name: user_matches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_matches (
    id uuid NOT NULL,
    user1_id uuid NOT NULL,
    user2_id uuid NOT NULL,
    compatibility_score numeric(5,2) NOT NULL,
    common_interests jsonb,
    match_reason text,
    status public.enum_user_matches_status DEFAULT 'pending'::public.enum_user_matches_status,
    venue_id uuid,
    event_date date,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: user_penalties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_penalties (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    plan_id uuid,
    reason character varying(255) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: user_photos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_photos (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    file_path character varying(500) NOT NULL,
    file_size integer NOT NULL,
    mime_type character varying(50) NOT NULL,
    is_primary boolean DEFAULT false,
    display_order integer DEFAULT 0,
    uploaded_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: user_preferences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_preferences (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    preferred_venues character varying(255)[] DEFAULT (ARRAY[]::character varying[])::character varying(255)[],
    preferred_crowd_size character varying(20),
    music_preference character varying(255)[] DEFAULT (ARRAY[]::character varying[])::character varying(255)[],
    drink_preference character varying(255)[] DEFAULT (ARRAY[]::character varying[])::character varying(255)[],
    smoking_preference character varying(20),
    preferred_genders character varying(255)[] DEFAULT (ARRAY[]::character varying[])::character varying(255)[],
    min_age_preference integer DEFAULT 18,
    max_age_preference integer DEFAULT 60,
    min_budget integer,
    max_budget integer,
    budget_range character varying(20),
    party_time_preference character varying(20),
    group_size_preference character varying(20),
    match_distance_km integer DEFAULT 10,
    show_me_in_matching boolean DEFAULT true,
    booking_alerts_enabled boolean DEFAULT false,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: user_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_profiles (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    display_name character varying(100),
    bio text,
    gender character varying(20),
    city character varying(100),
    occupation character varying(100),
    company character varying(100),
    education character varying(200),
    relationship_status character varying(20),
    looking_for character varying(255)[] DEFAULT (ARRAY[]::character varying[])::character varying(255)[],
    instagram_handle character varying(50),
    spotify_profile character varying(255),
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    nightlife_preference character varying(255)[] DEFAULT (ARRAY[]::character varying[])::character varying(255)[],
    interests character varying(255)[] DEFAULT (ARRAY[]::character varying[])::character varying(255)[],
    daily_match_requests_count integer DEFAULT 0,
    daily_likes_count integer DEFAULT 0,
    daily_posts_count integer DEFAULT 0,
    last_activity_date timestamp with time zone
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid NOT NULL,
    email character varying(255) NOT NULL,
    phone character varying(20) NOT NULL,
    password_hash character varying(255) NOT NULL,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    date_of_birth date NOT NULL,
    role public.enum_users_role DEFAULT 'customer'::public.enum_users_role NOT NULL,
    is_verified boolean DEFAULT false,
    is_active boolean DEFAULT true,
    mfa_enabled boolean DEFAULT false,
    mfa_secret character varying(255),
    profile_image_url character varying(500),
    last_login_at timestamp with time zone,
    is_online boolean DEFAULT false,
    last_active_at timestamp with time zone,
    no_show_count integer DEFAULT 0,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    fcm_token character varying(500),
    cleared_notifications_at timestamp with time zone,
    block_count integer DEFAULT 0,
    is_autoblocked boolean DEFAULT false,
    autoblocked_reason text
);


--
-- Name: venue_compliance_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.venue_compliance_logs (
    id uuid NOT NULL,
    venue_id uuid NOT NULL,
    event_type character varying(50) NOT NULL,
    actor_email character varying(255),
    ip_address character varying(45),
    metadata jsonb,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: venue_images; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.venue_images (
    id uuid NOT NULL,
    venue_id uuid NOT NULL,
    file_path character varying(500) NOT NULL,
    file_size integer NOT NULL,
    mime_type character varying(50) NOT NULL,
    image_type public.enum_venue_images_image_type NOT NULL,
    caption character varying(255),
    is_primary boolean DEFAULT false,
    display_order integer DEFAULT 0,
    uploaded_by uuid NOT NULL,
    uploaded_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: venues; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.venues (
    id uuid NOT NULL,
    owner_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    slug character varying(255) NOT NULL,
    tagline character varying(255),
    description text,
    category public.enum_venues_category NOT NULL,
    tags jsonb DEFAULT '[]'::jsonb,
    address_line1 character varying(255) NOT NULL,
    address_line2 character varying(255),
    area character varying(100),
    city character varying(100) NOT NULL,
    state character varying(100) NOT NULL,
    postal_code character varying(10) NOT NULL,
    country character varying(100) DEFAULT 'India'::character varying,
    latitude numeric(10,8),
    longitude numeric(11,8),
    display_order integer DEFAULT 0 NOT NULL,
    nearest_landmark character varying(255),
    directions text,
    phone character varying(20) NOT NULL,
    mobile character varying(20),
    whatsapp character varying(20),
    email character varying(255),
    website character varying(255),
    instagram character varying(255),
    facebook character varying(255),
    cp_name character varying(255),
    cp_designation character varying(255),
    cp_mobile character varying(20),
    cp_email character varying(255),
    alt_cp_name character varying(255),
    alt_cp_designation character varying(255),
    alt_cp_mobile character varying(20),
    alt_cp_email character varying(255),
    capacity integer DEFAULT 100 NOT NULL,
    seating_capacity integer,
    standing_capacity integer,
    opening_time time without time zone,
    closing_time time without time zone,
    days_open jsonb DEFAULT '[]'::jsonb,
    age_limit integer DEFAULT 21,
    cover_charge_male numeric(10,2),
    cover_charge_female numeric(10,2),
    discount_percentage numeric(5,2) DEFAULT 0,
    table_booking_charges numeric(10,2) DEFAULT 0,
    group_party_charge_per_person numeric(10,2) DEFAULT 0,
    group_party_discount_percentage numeric(5,2) DEFAULT 0,
    couple_entry_fee numeric(10,2) DEFAULT 0,
    dress_code character varying(255),
    cuisine_types jsonb DEFAULT '[]'::jsonb,
    music_types jsonb DEFAULT '[]'::jsonb,
    amenities jsonb DEFAULT '{}'::jsonb,
    pan_number character varying(20),
    gst_number character varying(20),
    fssai_license character varying(50),
    liquor_license character varying(50),
    fire_safety_cert character varying(50),
    trade_license character varying(50),
    bank_account_number character varying(50),
    bank_ifsc character varying(20),
    bank_name character varying(100),
    average_rating numeric(3,2) DEFAULT 0,
    total_reviews integer DEFAULT 0,
    status character varying(50) DEFAULT 'pending'::character varying,
    terms_accepted_at timestamp with time zone,
    confirmation_token character varying(128),
    confirmation_token_expires_at timestamp with time zone,
    owner_email_sent_at timestamp with time zone,
    owner_confirmed_at timestamp with time zone,
    featured boolean DEFAULT false,
    is_active boolean DEFAULT true,
    is_verified boolean DEFAULT false,
    is_premium boolean DEFAULT false,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Data for Name: SubscriptionPackages; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public."SubscriptionPackages" (id, name, tier, price, duration_days, daily_match_requests, daily_likes, daily_posts, superlikes_per_cycle, boosts_per_cycle, has_hide_profile, has_priority_visibility, has_trust_badge, has_elite_badge, can_see_who_liked, is_active, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: UserSubscriptions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public."UserSubscriptions" (id, user_id, package_id, status, start_date, end_date, superlikes_remaining, boosts_remaining, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: ads; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ads (id, type, venue_id, city, area, image_path, from_date, to_date, is_active, social_links, created_at, updated_at, about_event, title) FROM stdin;
2c4a2f2b-7cbb-4e20-a0da-678ba3413078	Party	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	Pune	Hinjewadi	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\gallery\\1781689258330_dca393dcae21194c.compressed.webp	2026-06-17 05:30:00+05:30	2026-12-31 05:30:00+05:30	t	[]	2026-06-17 15:10:58.835+05:30	2026-06-30 15:39:51.485+05:30	This is a about Tettoricca testing text.	SUFI NIGHT
7ec8bc49-28a7-46fa-8de1-08bbc0aef35a	Party	17887092-ea6a-4102-82a0-06aefdb1d79d	Pune	Viman Nagar	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\gallery\\1782281680449_5d9f5b8589d4e53f.compressed.webp	2026-06-24 05:30:00+05:30	2026-07-31 05:30:00+05:30	t	[]	2026-06-24 11:44:41.409+05:30	2026-06-30 15:40:35.642+05:30	PUNE, ARE YOU READY? \r\n\r\nThis weekend, the party moves to Lova All Day Kitchen & Bar, Viman Nagar! \r\nAvailable now on LUNARA	All Day Offer
d456beb8-d2ea-4a81-9111-3723c5ac25ad	Ads	\N	Pune	\N	uploads\\venues\\temp\\gallery\\1783002835179_f1c4ff6dcca6b082.compressed.webp	2026-06-16 05:30:00+05:30	2026-12-31 05:30:00+05:30	t	[]	2026-06-16 18:34:30.131+05:30	2026-07-02 20:04:07.048+05:30	test three	\N
47e96b82-58f1-490a-9e14-51d00ad070f0	Ads	\N	Pune	\N	uploads\\venues\\temp\\gallery\\1783002923766_bd18a84da1fc3362.compressed.webp	2026-07-02 05:30:00+05:30	2026-12-31 05:30:00+05:30	t	[]	2026-07-02 20:05:41.693+05:30	2026-07-02 20:05:41.693+05:30	\N	\N
94308353-af86-486c-982e-8017b526e39b	Party	a34456dc-fc25-4092-aae8-d3f8fd29d76f	Pune	Hinjewadi	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\gallery\\1783335603751_cd3332e764dce98d.compressed.webp	2026-07-06 05:30:00+05:30	2026-12-31 05:30:00+05:30	t	[]	2026-07-06 16:30:06.393+05:30	2026-07-06 16:31:36.446+05:30	Where cocktails meet unforgettable vibes.\r\n\r\nStep into a night of handcrafted cocktails, electrifying DJ beats, irresistible food, and an atmosphere that keeps the energy alive until the last song.\r\n\r\n✨ Premium Cocktails\r\n🎧 Live DJ\r\n💃 Dance All Night\r\n🍽️ Delicious Food\r\n🌃 Unmatched Nightlife Experience\r\n\r\nGather your crew, dress to impress, and let the night take over.\r\n\r\n📍 Favela | ONYX, Pune\r\n\r\nBook your table now—because the best nights are never planned, they're experienced. 🥂	Velvet Nights
823196b3-2d97-4113-a199-946eecf81d3f	Party	4311111f-8e89-4016-a39c-faf3d12eacf9	Pune	Hinjewadi	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\gallery\\1783335210769_9992ed3d44bd0e20.compressed.webp	2026-07-06 05:30:00+05:30	2026-12-23 05:30:00+05:30	t	[]	2026-07-06 16:23:33.826+05:30	2026-07-07 17:55:32.222+05:30	🍸 Cocktail Nights Hit Different at Echho Pub! ✨\r\n\r\nUnwind with expertly crafted cocktails, electrifying DJ beats, delicious food, and an atmosphere that keeps the party alive all night.\r\n\r\nWhether you're planning a date night, celebrating with friends, or just chasing the weekend vibes—this is where the night begins.\r\n\r\n📍 Echho, Pune\r\n\r\n🥂 Signature Cocktails\r\n🎧 Live DJ\r\n🍽️ Great Food\r\n✨ Premium Ambience\r\n\r\nBook your table now and raise a toast to unforgettable nights! 🍸	Cocktail Party
\.


--
-- Data for Name: booking_members; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.booking_members (id, group_booking_id, user_id, display_name, share_amount, payment_status, paid_at, transaction_id, is_organizer, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: booking_table_packages; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.booking_table_packages (id, venue_id, name, label, description, price, max_guests, bottles_included, is_active, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: bookings; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.bookings (id, booking_number, user_id, venue_id, booking_date, start_time, end_time, number_of_guests, total_amount, deposit_amount, commission_amount, status, payment_status, is_group_booking, cancellation_reason, cancelled_at, special_requests, going_mode, table_package, payment_mode, ticket_code, added_to_wallet, created_at, updated_at, party_subject, party_requirement, party_description, is_large_party_request, admin_approval_status, mobile_number, optional_mobile_number, admin_payment_link, admin_payment_amount) FROM stdin;
05133a95-b573-42b6-89a1-64e423b97b56	BKMR3HHE146YRI	55d60813-00a5-4059-821f-8bf6da1d6262	4311111f-8e89-4016-a39c-faf3d12eacf9	2026-07-10	18:30:00	\N	25	1000.00	0.00	100.00	pending	pending	f	\N	\N	\N	party_request	none	\N	\N	f	2026-07-02 18:01:36.52+05:30	2026-07-02 18:04:40.697+05:30	Birthday	Cake	Please arrange	t	approved	\N	\N	\N	\N
bc4fc505-6918-400d-97fd-4e523150d07b	BKMR3I6L76WNH5	55d60813-00a5-4059-821f-8bf6da1d6262	b50d85dd-ef32-4753-9e53-159ac11d8046	2026-07-04	22:00:00	\N	25	0.00	0.00	0.00	pending	pending	f	\N	\N	\N	party_request	none	\N	\N	f	2026-07-02 18:21:12.209+05:30	2026-07-02 18:21:12.209+05:30	Booking for group party 	Diner and drink required	Diner and drink required	t	pending	\N	\N	\N	\N
3b0243b3-945c-48c0-8e42-93df993e72af	BKMR3J3JOBXYHS	55d60813-00a5-4059-821f-8bf6da1d6262	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	2026-07-05	22:00:00	\N	25	0.00	0.00	0.00	pending	pending	f	\N	\N	\N	party_request	none	\N	\N	f	2026-07-02 18:46:49.882+05:30	2026-07-02 18:46:49.882+05:30	Test Group party	Diner and drink	This is the group party booking.	t	pending	\N	\N	\N	\N
6ea65e8d-ce1e-4630-ab74-8189f909c31f	BKMR3M1EOEFNF7	1aa75230-368e-4dc9-aaec-378904c1377b	4311111f-8e89-4016-a39c-faf3d12eacf9	2026-07-02	13:00:00	\N	21	5000.00	0.00	500.00	pending	pending	f	\N	\N	\N	party_request	none	\N	\N	f	2026-07-02 20:09:08.941+05:30	2026-07-02 20:10:54.695+05:30	jungle meet	gun	welcome to Jungle	t	approved	\N	\N	\N	\N
3d07d80d-0b6e-4f0f-b464-b39452a5d5d2	BKMR4S3TFNX5GJ	55d60813-00a5-4059-821f-8bf6da1d6262	ab320228-2d2f-41da-9d07-c9f5a915211e	2026-07-03	22:00:00	\N	21	2000.00	0.00	200.00	pending	pending	f	\N	\N	\N	party_request	none	\N	\N	f	2026-07-03 15:46:45.25+05:30	2026-07-03 15:49:02.793+05:30	test	test	test	t	approved	\N	\N	\N	\N
c6df7a73-44c4-4feb-87d8-cd4dc207fb2c	BKMR96379E9U87	55d60813-00a5-4059-821f-8bf6da1d6262	a34456dc-fc25-4092-aae8-d3f8fd29d76f	2026-07-08	18:30:00	\N	22	0.00	0.00	0.00	pending	pending	f	\N	\N	\N	party_request	none	\N	\N	f	2026-07-06 17:29:15.842+05:30	2026-07-06 17:29:15.842+05:30	Test	Test	Test	t	pending	\N	\N	\N	\N
c78e56b6-4016-461d-9398-d25108246086	BKMRA8TKHMXR2G	55d60813-00a5-4059-821f-8bf6da1d6262	ab320228-2d2f-41da-9d07-c9f5a915211e	2026-07-09	18:30:00	\N	21	0.00	0.00	0.00	pending	pending	f	\N	\N	\N	party_request	none	\N	\N	f	2026-07-07 11:33:31.45+05:30	2026-07-07 11:33:31.45+05:30	Lunara Party	Lunara Party	Lunara Backend party	t	pending	\N	\N	\N	\N
\.


--
-- Data for Name: chat_subscriptions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.chat_subscriptions (id, conversation_id, paid_by_id, amount, days_granted, valid_until, status, subscription_type, requested_by_id, created_at, updated_at) FROM stdin;
990ef9d2-d4af-4af2-b035-ab2856086cf8	4867a86e-5b35-454b-8ce2-ab44139b65ab	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-07-14 13:02:44.091+05:30	active	paid	\N	2026-07-07 13:02:44.092+05:30	2026-07-07 13:02:44.092+05:30
e91280c3-29b5-4a66-b38d-ab852136d644	4867a86e-5b35-454b-8ce2-ab44139b65ab	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-07-21 13:02:44.091+05:30	active	paid	\N	2026-07-07 13:02:47.516+05:30	2026-07-07 13:02:47.516+05:30
309b777d-ab4c-47e9-b57a-cc8ebf6a1e7c	a2f3654f-bc94-4cf8-b806-9810774816d5	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-07-14 13:03:06.185+05:30	active	paid	\N	2026-07-07 13:03:06.186+05:30	2026-07-07 13:03:06.186+05:30
f6170878-f92d-4bf7-90ed-861db3edaa53	a2f3654f-bc94-4cf8-b806-9810774816d5	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-07-21 13:03:06.185+05:30	active	paid	\N	2026-07-07 13:03:07.794+05:30	2026-07-07 13:03:07.794+05:30
6b88fb72-f07d-4cda-bdaa-103e0354e88c	e0e3c8a2-60b1-444c-8cb7-e95df75a3045	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-07-14 13:03:26.711+05:30	active	paid	\N	2026-07-07 13:03:26.711+05:30	2026-07-07 13:03:26.711+05:30
911526f4-2546-4c9f-9165-0297e821ec45	a5119518-46d7-4d5e-9bf9-4390ccdcef78	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-07-14 13:17:56.514+05:30	active	paid	\N	2026-07-07 13:17:56.514+05:30	2026-07-07 13:17:56.514+05:30
5017669c-8ad2-40db-bae3-d488f75096f2	a5119518-46d7-4d5e-9bf9-4390ccdcef78	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-07-21 13:17:56.514+05:30	active	paid	\N	2026-07-07 13:21:20.819+05:30	2026-07-07 13:21:20.819+05:30
f6e333e2-f055-4798-9f1f-f0e448fdd7d0	a5119518-46d7-4d5e-9bf9-4390ccdcef78	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-07-28 13:17:56.514+05:30	active	paid	\N	2026-07-07 13:21:23.442+05:30	2026-07-07 13:21:23.442+05:30
bdd7f4f3-2951-418e-90ac-504f85521833	a5119518-46d7-4d5e-9bf9-4390ccdcef78	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-08-04 13:17:56.514+05:30	active	paid	\N	2026-07-07 13:21:24.021+05:30	2026-07-07 13:21:24.021+05:30
863eeae3-83bb-4f78-8cc7-03c71bd273d9	a5119518-46d7-4d5e-9bf9-4390ccdcef78	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-08-11 13:17:56.514+05:30	active	paid	\N	2026-07-07 13:21:25.528+05:30	2026-07-07 13:21:25.528+05:30
a8fc6d8e-34f1-4c19-b6ba-b8c93367b130	a5119518-46d7-4d5e-9bf9-4390ccdcef78	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-08-18 13:17:56.514+05:30	active	paid	\N	2026-07-07 13:21:25.845+05:30	2026-07-07 13:21:25.845+05:30
e8090d0e-ecd5-4e63-8d52-169eda3ed5d0	a5119518-46d7-4d5e-9bf9-4390ccdcef78	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-08-25 13:17:56.514+05:30	active	paid	\N	2026-07-07 13:21:26.17+05:30	2026-07-07 13:21:26.17+05:30
a1e26d09-9122-499e-b387-48ca9da7aefc	a5119518-46d7-4d5e-9bf9-4390ccdcef78	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-09-01 13:17:56.514+05:30	active	paid	\N	2026-07-07 13:21:26.532+05:30	2026-07-07 13:21:26.532+05:30
9bd39fbb-19a7-4207-9b32-278787e9be49	a5119518-46d7-4d5e-9bf9-4390ccdcef78	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-09-08 13:17:56.514+05:30	active	paid	\N	2026-07-07 13:21:26.824+05:30	2026-07-07 13:21:26.824+05:30
4742d52b-2101-4c3b-bbbe-a33dcd3d2f5e	a5119518-46d7-4d5e-9bf9-4390ccdcef78	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-09-15 13:17:56.514+05:30	active	paid	\N	2026-07-07 13:21:27.122+05:30	2026-07-07 13:21:27.122+05:30
9ca62fbb-8bd7-4d4f-8892-daa166092937	a5119518-46d7-4d5e-9bf9-4390ccdcef78	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-09-22 13:17:56.514+05:30	active	paid	\N	2026-07-07 13:21:27.443+05:30	2026-07-07 13:21:27.443+05:30
4123e414-d18d-40d3-96dc-6fff1db3f2c9	a5119518-46d7-4d5e-9bf9-4390ccdcef78	2bac9feb-8e54-44cd-9393-0f84e9b236be	100.00	7	2026-09-29 13:17:56.514+05:30	active	paid	\N	2026-07-07 13:21:27.776+05:30	2026-07-07 13:21:27.776+05:30
\.


--
-- Data for Name: cities; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cities (id, name, state, is_active, display_order, created_at, updated_at) FROM stdin;
3c1d946c-4dd3-4fb5-9eb5-91c5059ecf50	Pune	Maharashtra	t	1	2026-07-01 19:09:16.733+05:30	2026-07-01 19:09:16.733+05:30
\.


--
-- Data for Name: community_guidelines; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.community_guidelines (id, title, content, category, is_active, display_order, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: conversations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.conversations (id, participant_one, participant_two, last_message_id, last_message_at, last_message_preview, unread_one, unread_two, status, context_type, context_id, created_at, updated_at) FROM stdin;
beeede8e-1524-4ee7-b8f2-81045b39c7f0	444f8f5f-9c18-43fd-956a-b0e41a79292b	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	29ba4d30-fd29-421b-9a9d-fcc44d521708	2026-06-23 17:08:04.522+05:30	pora	3	0	active	\N	\N	2026-06-23 15:58:35.99+05:30	2026-06-23 17:08:04.527+05:30
3dd1c0ae-9a6f-4e8b-81ec-be44de008c86	55d60813-00a5-4059-821f-8bf6da1d6262	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	a6a8cebd-5c1b-43b2-8dbd-472d4993ffc7	2026-06-24 13:52:53.373+05:30	hello	0	0	active	\N	\N	2026-06-24 13:51:58.009+05:30	2026-06-24 13:53:23.25+05:30
981128a2-41fa-494e-b932-6eac32022d49	444f8f5f-9c18-43fd-956a-b0e41a79292b	ccb35417-49f8-474d-8d33-6f4e9d7738c0	\N	\N	\N	0	0	active	\N	\N	2026-06-23 15:58:17.845+05:30	2026-06-23 15:58:17.845+05:30
267213de-f682-432b-bb5c-77fd25dba68c	55d60813-00a5-4059-821f-8bf6da1d6262	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	e1d94178-4201-4240-aff6-5d59b71b431a	2026-07-01 17:40:47.645+05:30	hello	0	0	active	\N	\N	2026-06-22 17:21:48.966+05:30	2026-07-02 12:16:24.837+05:30
2a001e2d-7282-4014-b397-c2e59b4502d0	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	\N	\N	\N	0	0	active	\N	\N	2026-07-03 21:06:39.513+05:30	2026-07-03 21:06:39.513+05:30
39eaf617-f271-4ffb-a88d-606e4063ce5d	444f8f5f-9c18-43fd-956a-b0e41a79292b	55d60813-00a5-4059-821f-8bf6da1d6262	0dfa699f-8aa1-4235-b1ec-ded7b78ccb56	2026-06-23 16:26:33.219+05:30	hello sir	0	0	active	\N	\N	2026-06-23 15:46:40.375+05:30	2026-06-23 16:26:42.364+05:30
ad103d48-d690-473c-8f05-4b75c849834d	55d60813-00a5-4059-821f-8bf6da1d6262	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	adf7693f-672e-4e05-934e-ab72367796a3	2026-07-01 17:38:43.673+05:30	test 1	0	0	active	\N	\N	2026-06-24 16:34:40.763+05:30	2026-07-01 17:40:02.523+05:30
c3615683-4c0d-41be-b92e-1575424a8004	1aa75230-368e-4dc9-aaec-378904c1377b	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	ad07b90e-0af9-430f-9a3d-67531edf6501	2026-06-23 15:54:20.804+05:30	hello	0	0	active	\N	\N	2026-06-23 15:54:14.431+05:30	2026-06-23 16:28:42.745+05:30
a2f3654f-bc94-4cf8-b806-9810774816d5	2bac9feb-8e54-44cd-9393-0f84e9b236be	6b5bd1f2-3d3f-4533-bfd2-61de0b21e299	\N	\N	\N	0	0	active	\N	\N	2026-07-07 13:03:03.714+05:30	2026-07-07 13:03:03.714+05:30
e0e3c8a2-60b1-444c-8cb7-e95df75a3045	2bac9feb-8e54-44cd-9393-0f84e9b236be	6d861d92-f6c6-45f7-b444-7315a2685465	\N	\N	\N	0	0	active	\N	\N	2026-07-07 13:03:24.53+05:30	2026-07-07 13:03:24.53+05:30
a5119518-46d7-4d5e-9bf9-4390ccdcef78	1aa75230-368e-4dc9-aaec-378904c1377b	2bac9feb-8e54-44cd-9393-0f84e9b236be	\N	\N	\N	0	0	active	\N	\N	2026-07-07 13:13:49.533+05:30	2026-07-07 13:13:49.533+05:30
4867a86e-5b35-454b-8ce2-ab44139b65ab	2bac9feb-8e54-44cd-9393-0f84e9b236be	55d60813-00a5-4059-821f-8bf6da1d6262	99b56fa8-45a4-4fbf-87bc-73945f4e8974	2026-07-04 16:20:22.664+05:30	⚡ Dance floor or VIP lounge?	0	0	active	\N	\N	2026-06-25 18:14:21.055+05:30	2026-07-07 13:25:03.823+05:30
e5d99a31-018c-4b52-b3d9-e2c7a922a47e	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	2a20a0e9-0c21-4771-8e8d-059960ae18b6	2026-07-01 17:43:07.687+05:30	5	0	0	active	\N	\N	2026-06-22 15:08:26.298+05:30	2026-07-07 19:26:34.533+05:30
\.


--
-- Data for Name: email_verifications; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.email_verifications (id, user_id, token, verified_at, expires_at, created_at) FROM stdin;
02bfad5a-4519-4da9-b2b2-2fb844d7568b	ccb35417-49f8-474d-8d33-6f4e9d7738c0	a5f248392c9c37a4a137b86df8ffb1effcd9350efcbcc2f51b7cac61e09227b7	2026-06-16 15:35:40.931+05:30	2026-06-17 15:35:40.817+05:30	2026-06-16 15:35:40.817+05:30
076bdfc6-8fb4-4ad1-9623-6651e37830c0	681a88ab-5628-4081-af04-22aeb74daef2	2b850dfb7504fad04b79298e8cced723494f39f90276d336ce6a1ece03bcd7ac	\N	2026-06-17 15:59:26.212+05:30	2026-06-16 15:59:26.217+05:30
706c2d61-90b2-4595-9494-8effc7e36475	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	7bc5a68c41d4f4563bb36e000415b840b5906310c6f3a79dc80d264d9520d783	\N	2026-06-17 15:59:36.415+05:30	2026-06-16 15:59:36.42+05:30
6ddf3105-1eb5-4584-91d2-e6dcf90da5e1	55d60813-00a5-4059-821f-8bf6da1d6262	5e2cae5c5eb33a5a575cc8b5ac17e99d25c9c37d6452aeab2316499359191daf	\N	2026-06-17 16:59:20.322+05:30	2026-06-16 16:59:20.327+05:30
f738a964-28de-4318-bb3e-4f7e17547ae1	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	941067016030b6f01d912d0e0e03ee2688946bcdbdec253b917182cfe2cbc81b	\N	2026-06-17 18:32:21.69+05:30	2026-06-16 18:32:21.694+05:30
31e976d5-920d-4ef5-a181-396e0d75333e	1aa75230-368e-4dc9-aaec-378904c1377b	daf50f35c6eb7dc470073693bdd358502d5773786d9deda70a0091497739f288	\N	2026-06-24 14:36:31.134+05:30	2026-06-23 14:36:31.141+05:30
9596e5a8-5bf9-48f1-ba56-8718de778903	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	f0eff4ebec5649df579e4f7627adb33cb6fcfca3c38eb9d0886fdc12c6b7f8ba	\N	2026-06-24 14:49:06.205+05:30	2026-06-23 14:49:06.209+05:30
8d7025c0-35f7-4c6e-a432-c4a277f280ef	444f8f5f-9c18-43fd-956a-b0e41a79292b	09976ce362639c37515c28b9d6d755282c964aa88dc6d68fc7b62e26969db734	\N	2026-06-24 15:40:11.514+05:30	2026-06-23 15:40:11.518+05:30
94d3fdfd-0860-4134-9bf4-7c1793a0404d	6b5bd1f2-3d3f-4533-bfd2-61de0b21e299	fb326907b4f57d007245485d7ab00a79e0ffe877cc9362a7a684127fe170604c	\N	2026-06-26 12:16:15.341+05:30	2026-06-25 12:16:15.349+05:30
a1a44fd7-6736-4b0c-b535-a13515d684cf	2bac9feb-8e54-44cd-9393-0f84e9b236be	be95753b8b289f7d169b45937f68258e4ffb452168d33275c4af9db3ca06e4e1	\N	2026-06-26 15:42:49.815+05:30	2026-06-25 15:42:49.819+05:30
df096bcf-7b23-440a-b65e-4595fdfe0fa2	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	4e92c2968e8703b107a163050d15e255ae36e0ce22bd5195b4722a2a12ce1db3	\N	2026-07-01 15:26:08.829+05:30	2026-06-30 15:26:08.868+05:30
0699d5ca-355d-454c-898a-6856dacd1119	dd2efb63-a121-4f55-ac86-8c43da14fcef	f471e46719fa11946b8f0bb806bff639c5eb42b0b5cfef08da4c03afa82a61b7	\N	2026-07-01 17:53:29.226+05:30	2026-06-30 17:53:29.231+05:30
8329ae32-b4b8-42d1-b8a3-d7c262576e4e	6bdc7560-5b6c-4cb4-b72b-1666fddfa5f2	787d0ca8e470dfe358b6af2e92bc4bbf8587d3aefd93a84ae671a8d6043e7b48	\N	2026-07-02 15:05:53.942+05:30	2026-07-01 15:05:53.949+05:30
27309067-b406-4f1b-b686-dcc342309ffb	64786496-e9b0-4ecb-8285-3095ef3bcf16	f3dd3d399ebe44128048d0d5abdfcae1bed33c3977bf65a58566624b61fd7d34	\N	2026-07-02 15:38:30.403+05:30	2026-07-01 15:38:30.406+05:30
ad71d256-fa76-4b33-a1a5-34fe5da2fe33	326982fd-3909-4791-b8d4-66efbfaf2734	33e6732e13237a106042f255473d0ced7c5a8f4b5228e452888e9a54937ece9b	\N	2026-07-03 14:55:53.894+05:30	2026-07-02 14:55:53.9+05:30
1e4e55c3-8a06-44f5-babd-7659730cbd97	400a3048-dba7-4d56-9d10-cb5d7c0f18a0	8422bfe306f6f414fc24673f062a8ac4bfdc4f3023bb1260fddd8adda27badb7	\N	2026-07-03 20:13:31.643+05:30	2026-07-02 20:13:31.649+05:30
ebdb9234-4222-42be-a457-39c825db4726	37c1bb21-26d1-4082-a1da-871a16b0b232	b80eafe9aff460df5ef95a3019fa1840b001aaeeed8528cf7ef64be0c3fd8291	\N	2026-07-03 20:23:18.62+05:30	2026-07-02 20:23:18.625+05:30
409dae63-5459-4e7b-af01-dabc35a12685	7198fd2d-abfc-4ebb-b819-00ce75f493d2	13779f538cf290847fa3a1125605bf9e3e30b074e5106a734a01a80b8fb645af	\N	2026-07-04 12:43:50.251+05:30	2026-07-03 12:43:50.257+05:30
8079862d-2698-4679-ba31-f2c7b4de50d6	dd2f25ca-d7e1-4670-a9c3-24478c9e8c3e	665d6e6d1530014b07f9a375eb9fb376e1da4d466b3c892f6373f2e198170d62	\N	2026-07-04 13:21:37.209+05:30	2026-07-03 13:21:37.213+05:30
5d1f72a5-6647-40ae-823e-00ae8ac37897	e4bcd759-8b6d-4900-abd8-f11ebbc830a4	6d1f6a96a8386f52d25988a244678b09d0b3beb24ee404acd185d3b880af0503	\N	2026-07-04 15:15:40.29+05:30	2026-07-03 15:15:40.294+05:30
e371bd8a-9b77-4d4b-bc3b-b3bd13f84edf	b5bf9672-2e0f-4616-838e-5f8591862855	b2ffc379efc42ee6cec0e585a737cae56714016aeb2a0e9bd2c6cc79977defde	\N	2026-07-07 16:45:28.842+05:30	2026-07-06 16:45:28.856+05:30
8205cbcc-66f7-4031-b606-297ab533606c	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	49afb3cdbbc48ed8bd50312a0acff0662148b0ce3feed68c4ce919a7c5d71999	\N	2026-07-07 17:33:01.275+05:30	2026-07-06 17:33:01.282+05:30
a0da6c00-0e11-44b7-8544-ee91bae2d10f	71da26fc-a3a3-434a-aa6f-73220fd29fdd	756e7f60dadc72ecec5121d18d3def32badd6b5c7a4c16e4a9f020d14c6c4912	\N	2026-07-07 18:19:39.488+05:30	2026-07-06 18:19:39.495+05:30
915fe4df-785a-4bdb-b9d2-65e587531609	095d1b94-1a8b-47c2-b912-c9031f0d9fcb	1e0708bf30f64886b901cc7605c50e13cfa113c49d53354aa16c086778952f0c	\N	2026-07-07 18:56:56.668+05:30	2026-07-06 18:56:56.676+05:30
51774ffb-10a9-4b4f-92f6-0736bd868484	6d861d92-f6c6-45f7-b444-7315a2685465	17c3cced29f8bfb9469cd2cad8e5702806c0ad7fab86aefe300b15936ab529e2	\N	2026-07-07 19:20:58.578+05:30	2026-07-06 19:20:58.586+05:30
\.


--
-- Data for Name: group_bookings; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.group_bookings (id, booking_id, organizer_id, group_name, split_payment_enabled, split_type, total_members, confirmed_members, paid_members, invitation_code, invitation_expires_at, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: group_parties; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.group_parties (id, user_id, venue_id, number_of_friends, table_booking_charge, discount_amount, total_amount, status, payment_status, payment_id, party_date, created_at, updated_at, mobile_number, optional_mobile_number) FROM stdin;
\.


--
-- Data for Name: help_articles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.help_articles (id, title, content, category, is_published, display_order, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: legal_documents; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.legal_documents (id, title, type, content, version, is_active, effective_date, created_at, updated_at) FROM stdin;
7952469b-75a7-4ddf-bb5f-9bf155bda0db	Terms And Conditions	terms_of_service	Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since 1966, when designers at Letraset and James Mosley, the librarian at St Bride Printing Library in London, took a 1914 Cicero translation and scrambled it to make dummy text for Letraset's Body Type sheets. It has survived not only many decades, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised thanks to these sheets and more recently with desktop publishing software including versions of Lorem Ipsum.	1.0	t	2026-06-22	2026-06-22 15:25:30.197+05:30	2026-06-22 15:25:30.197+05:30
\.


--
-- Data for Name: messages; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.messages (id, conversation_id, sender_id, type, content, media_url, media_mime_type, invitation_ref, invitation_ref_type, invitation_time, invitation_status, status, read_at, deleted_at, created_at, updated_at) FROM stdin;
51a77baa-3c56-4d4b-a687-c4a5fe51be56	39eaf617-f271-4ffb-a88d-606e4063ce5d	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	hii	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:26:42.36+05:30	\N	2026-06-23 15:58:48.414+05:30	2026-06-23 16:26:42.36+05:30
8903b568-bf12-4ea4-a5b1-9127c29216eb	39eaf617-f271-4ffb-a88d-606e4063ce5d	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	hii	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:26:42.36+05:30	\N	2026-06-23 15:58:56.332+05:30	2026-06-23 16:26:42.36+05:30
c9b0c211-4d46-4328-88ca-1a082d620ae7	e5d99a31-018c-4b52-b3d9-e2c7a922a47e	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	text	hi 👋	\N	\N	\N	\N	\N	\N	read	2026-06-22 17:24:27.211+05:30	\N	2026-06-22 15:08:32.575+05:30	2026-06-22 17:24:27.212+05:30
81562f98-cbb1-4b34-8e68-d318a5e027ea	39eaf617-f271-4ffb-a88d-606e4063ce5d	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	hii	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:26:42.36+05:30	\N	2026-06-23 16:23:00.712+05:30	2026-06-23 16:26:42.36+05:30
b98888a5-92aa-4474-b6e2-835238239251	39eaf617-f271-4ffb-a88d-606e4063ce5d	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	hii	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:26:42.36+05:30	\N	2026-06-23 16:24:36.193+05:30	2026-06-23 16:26:42.36+05:30
b7b988c6-59f8-40cc-ac4a-b068a4de297a	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	hello	\N	\N	\N	\N	\N	\N	read	2026-06-22 17:50:05.068+05:30	\N	2026-06-22 17:21:53.89+05:30	2026-06-22 17:50:05.069+05:30
32171640-0699-4f0a-9deb-de99ede4bf02	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	hi	\N	\N	\N	\N	\N	\N	read	2026-06-22 17:50:05.068+05:30	\N	2026-06-22 17:24:02.146+05:30	2026-06-22 17:50:05.069+05:30
4e240c97-053f-4be4-87d2-9ac1ce1ad6a1	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	hhhj	\N	\N	\N	\N	\N	\N	read	2026-06-22 17:50:05.068+05:30	\N	2026-06-22 17:28:32.522+05:30	2026-06-22 17:50:05.069+05:30
a7e06ac0-8543-42b9-86e5-05a099c57e67	39eaf617-f271-4ffb-a88d-606e4063ce5d	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	hii	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:26:42.36+05:30	\N	2026-06-23 16:26:07.507+05:30	2026-06-23 16:26:42.36+05:30
4a45161b-83d6-4a14-9f77-f29a85b1ff10	39eaf617-f271-4ffb-a88d-606e4063ce5d	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	hello sir	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:26:42.36+05:30	\N	2026-06-23 16:26:21.544+05:30	2026-06-23 16:26:42.36+05:30
889fc35c-032f-4f62-a3fb-e541c6d18d62	267213de-f682-432b-bb5c-77fd25dba68c	55d60813-00a5-4059-821f-8bf6da1d6262	text	Test msg	\N	\N	\N	\N	\N	\N	read	2026-06-22 18:06:00.973+05:30	\N	2026-06-22 17:50:13.723+05:30	2026-06-22 18:06:00.974+05:30
d54407cb-93cf-4b8f-89f4-1026a6a203a1	267213de-f682-432b-bb5c-77fd25dba68c	55d60813-00a5-4059-821f-8bf6da1d6262	text	ok	\N	\N	\N	\N	\N	\N	read	2026-06-22 18:06:00.973+05:30	\N	2026-06-22 18:05:22.336+05:30	2026-06-22 18:06:00.974+05:30
79fa6e15-2011-4064-867d-af0e9d9a86f8	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	kkko	\N	\N	\N	\N	\N	\N	read	2026-06-22 18:06:08.773+05:30	\N	2026-06-22 18:06:08.58+05:30	2026-06-22 18:06:08.774+05:30
e5c41fd5-20e8-4248-b6de-c08239a0c58c	267213de-f682-432b-bb5c-77fd25dba68c	55d60813-00a5-4059-821f-8bf6da1d6262	text	pu okok	\N	\N	\N	\N	\N	\N	read	2026-06-22 18:09:16.876+05:30	\N	2026-06-22 18:07:11.72+05:30	2026-06-22 18:09:16.876+05:30
0dfa699f-8aa1-4235-b1ec-ded7b78ccb56	39eaf617-f271-4ffb-a88d-606e4063ce5d	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	hello sir	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:26:42.36+05:30	\N	2026-06-23 16:26:33.219+05:30	2026-06-23 16:26:42.36+05:30
a631896d-258b-4196-8d81-dfaa85997d59	267213de-f682-432b-bb5c-77fd25dba68c	55d60813-00a5-4059-821f-8bf6da1d6262	text	hello vishal	\N	\N	\N	\N	\N	\N	read	2026-06-23 11:59:41.511+05:30	\N	2026-06-23 11:26:30.859+05:30	2026-06-23 11:59:41.511+05:30
7b1c7165-b0e1-4c55-b771-01b6b05a266f	267213de-f682-432b-bb5c-77fd25dba68c	55d60813-00a5-4059-821f-8bf6da1d6262	text	test message	\N	\N	\N	\N	\N	\N	read	2026-06-23 11:59:41.511+05:30	\N	2026-06-23 11:35:59.221+05:30	2026-06-23 11:59:41.511+05:30
6448e305-1e1f-4e02-a681-dd786b882b89	267213de-f682-432b-bb5c-77fd25dba68c	55d60813-00a5-4059-821f-8bf6da1d6262	text	test msg for notification	\N	\N	\N	\N	\N	\N	read	2026-06-23 11:59:41.511+05:30	\N	2026-06-23 11:58:07.843+05:30	2026-06-23 11:59:41.511+05:30
e8496987-7aec-449e-a5ce-d164a538a9b5	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	hello Sir	\N	\N	\N	\N	\N	\N	read	2026-06-23 11:59:49.662+05:30	\N	2026-06-23 11:59:45.778+05:30	2026-06-23 11:59:49.662+05:30
1b38c966-f44b-44a2-8cce-a104e3ccd736	beeede8e-1524-4ee7-b8f2-81045b39c7f0	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	hii	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:41:39.807+05:30	\N	2026-06-23 16:41:31.159+05:30	2026-06-23 16:41:39.808+05:30
b0f5084b-1c06-4bca-b2f8-12f7fa31b7e0	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	sir msg aalla ka	\N	\N	\N	\N	\N	\N	read	2026-06-23 12:01:08.775+05:30	\N	2026-06-23 12:00:14.876+05:30	2026-06-23 12:01:08.776+05:30
d44492f0-21aa-4e0b-8784-2fbc1c024779	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	kalpya msg bg	\N	\N	\N	\N	\N	\N	read	2026-06-23 12:01:08.775+05:30	\N	2026-06-23 12:00:55.063+05:30	2026-06-23 12:01:08.776+05:30
7930cbe6-ef14-4ed2-a7d5-da6fe4cc1e8b	beeede8e-1524-4ee7-b8f2-81045b39c7f0	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	ky	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:41:42.827+05:30	\N	2026-06-23 16:41:42.399+05:30	2026-06-23 16:41:42.827+05:30
20151acb-14ec-4cac-9a1f-e607e0f567f6	39eaf617-f271-4ffb-a88d-606e4063ce5d	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	hii	\N	\N	\N	\N	\N	\N	read	2026-06-23 15:50:37.767+05:30	\N	2026-06-23 15:46:43.403+05:30	2026-06-23 15:50:37.768+05:30
579778b0-d25a-492c-8bfb-f35de013af05	39eaf617-f271-4ffb-a88d-606e4063ce5d	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	hii	\N	\N	\N	\N	\N	\N	read	2026-06-23 15:50:37.767+05:30	\N	2026-06-23 15:46:49.061+05:30	2026-06-23 15:50:37.768+05:30
2b2a852f-245d-4755-8237-f8be0c3b5bb6	39eaf617-f271-4ffb-a88d-606e4063ce5d	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	ky kartay sir	\N	\N	\N	\N	\N	\N	read	2026-06-23 15:50:37.767+05:30	\N	2026-06-23 15:47:16.076+05:30	2026-06-23 15:50:37.768+05:30
067338e6-0001-41e6-85ef-f0681e8bb4b1	39eaf617-f271-4ffb-a88d-606e4063ce5d	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	hii	\N	\N	\N	\N	\N	\N	read	2026-06-23 15:50:37.767+05:30	\N	2026-06-23 15:50:09.326+05:30	2026-06-23 15:50:37.768+05:30
8fa2d77f-9c41-4871-8f01-ed70956e841d	beeede8e-1524-4ee7-b8f2-81045b39c7f0	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	kam kar tuja tuja	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:41:50.075+05:30	\N	2026-06-23 16:41:49.929+05:30	2026-06-23 16:41:50.075+05:30
83d560bc-8b18-4071-910e-078afd1c02da	beeede8e-1524-4ee7-b8f2-81045b39c7f0	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	hii	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:28:34.448+05:30	\N	2026-06-23 16:27:48.207+05:30	2026-06-23 16:28:34.448+05:30
6bd47b40-e63f-4a9d-86ac-799d0ff004e5	beeede8e-1524-4ee7-b8f2-81045b39c7f0	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	hii	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:28:34.448+05:30	\N	2026-06-23 15:58:38.375+05:30	2026-06-23 16:28:34.448+05:30
ad07b90e-0af9-430f-9a3d-67531edf6501	c3615683-4c0d-41be-b92e-1575424a8004	1aa75230-368e-4dc9-aaec-378904c1377b	text	hello	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:28:42.739+05:30	\N	2026-06-23 15:54:20.804+05:30	2026-06-23 16:28:42.739+05:30
c2308fa5-fbb3-4b69-adfe-b7b91c4c8b17	267213de-f682-432b-bb5c-77fd25dba68c	55d60813-00a5-4059-821f-8bf6da1d6262	text	bagla bhai msg	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:28:43.873+05:30	\N	2026-06-23 12:01:16.887+05:30	2026-06-23 16:28:43.873+05:30
67dd8213-6e4b-496c-a28d-29b0dcdc11d1	267213de-f682-432b-bb5c-77fd25dba68c	55d60813-00a5-4059-821f-8bf6da1d6262	text	aala msg	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:28:43.873+05:30	\N	2026-06-23 12:01:23.155+05:30	2026-06-23 16:28:43.873+05:30
4188a1f6-5a1c-411a-b0b6-af1e183621f9	beeede8e-1524-4ee7-b8f2-81045b39c7f0	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	observTion	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:41:53.553+05:30	\N	2026-06-23 16:41:53.296+05:30	2026-06-23 16:41:53.554+05:30
3cedeac8-cf6a-4bf9-8adb-2c83bcf7c963	267213de-f682-432b-bb5c-77fd25dba68c	55d60813-00a5-4059-821f-8bf6da1d6262	text	hi hello	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:40:13.513+05:30	\N	2026-06-23 16:38:57.602+05:30	2026-06-23 16:40:13.513+05:30
aa3a299f-294c-4f5c-8907-c0368a233a1c	267213de-f682-432b-bb5c-77fd25dba68c	55d60813-00a5-4059-821f-8bf6da1d6262	icebreaker	Favorite DJ in the city?	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:40:13.513+05:30	\N	2026-06-23 16:39:53.02+05:30	2026-06-23 16:40:13.513+05:30
ee36e7d8-977c-489f-ae4b-57a782e274f3	beeede8e-1524-4ee7-b8f2-81045b39c7f0	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	bye	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:41:29.036+05:30	\N	2026-06-23 16:28:36.98+05:30	2026-06-23 16:41:29.037+05:30
ef635e41-17e6-4637-9e60-71c26a60c599	beeede8e-1524-4ee7-b8f2-81045b39c7f0	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	bichyarya pori la kay bola tu	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:42:02.964+05:30	\N	2026-06-23 16:42:02.866+05:30	2026-06-23 16:42:02.964+05:30
cebbf6ad-5cca-4b0d-8efa-beb2bd4b07d5	beeede8e-1524-4ee7-b8f2-81045b39c7f0	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	under observation	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:42:03.898+05:30	\N	2026-06-23 16:42:03.682+05:30	2026-06-23 16:42:03.899+05:30
f1dde869-6b57-4f46-b591-814a4200b7e9	beeede8e-1524-4ee7-b8f2-81045b39c7f0	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	😆😆😆😀😃😅😃	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:42:12.189+05:30	\N	2026-06-23 16:42:11.999+05:30	2026-06-23 16:42:12.19+05:30
ce53060f-3ff6-4c49-a8a4-c9546cb03490	beeede8e-1524-4ee7-b8f2-81045b39c7f0	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	gp re	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:42:31.364+05:30	\N	2026-06-23 16:42:31.163+05:30	2026-06-23 16:42:31.365+05:30
c9af1a7e-438b-4a43-9117-9e734938b97a	beeede8e-1524-4ee7-b8f2-81045b39c7f0	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	mi ky bollo	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:42:26.977+05:30	\N	2026-06-23 16:42:14.07+05:30	2026-06-23 16:42:26.977+05:30
181fa9d0-27d3-4635-b487-901dae067d13	beeede8e-1524-4ee7-b8f2-81045b39c7f0	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	bahi	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:42:26.977+05:30	\N	2026-06-23 16:42:16.109+05:30	2026-06-23 16:42:26.977+05:30
84c7200c-db8a-46a5-a8e7-ec29612d895e	beeede8e-1524-4ee7-b8f2-81045b39c7f0	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	konala	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:42:26.977+05:30	\N	2026-06-23 16:42:18.589+05:30	2026-06-23 16:42:26.977+05:30
f280c6fa-de15-4d2b-bd06-ccd8b89781d9	beeede8e-1524-4ee7-b8f2-81045b39c7f0	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	ky gapp	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:44:52.639+05:30	\N	2026-06-23 16:43:03.665+05:30	2026-06-23 16:44:52.639+05:30
a0466b87-2279-471b-9408-6b2c35671a1d	beeede8e-1524-4ee7-b8f2-81045b39c7f0	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	vi4 br	\N	\N	\N	\N	\N	\N	delivered	\N	\N	2026-06-23 16:46:45.201+05:30	2026-06-23 16:46:45.201+05:30
bd494457-9df8-4bd8-9c74-baa267aff5be	beeede8e-1524-4ee7-b8f2-81045b39c7f0	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	mg ky zal tila	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:45:33.452+05:30	\N	2026-06-23 16:45:02.321+05:30	2026-06-23 16:45:33.453+05:30
c34d1b30-aa8d-4971-a339-cdcecb5bb698	beeede8e-1524-4ee7-b8f2-81045b39c7f0	444f8f5f-9c18-43fd-956a-b0e41a79292b	text	mala ky mahit	\N	\N	\N	\N	\N	\N	read	2026-06-23 16:45:47.529+05:30	\N	2026-06-23 16:45:47.386+05:30	2026-06-23 16:45:47.53+05:30
6f11c95d-657c-47eb-9453-b8f7ada83a17	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	icebreaker	What is your go-to signature cocktail?	\N	\N	\N	\N	\N	\N	read	2026-06-23 17:04:03.53+05:30	\N	2026-06-23 16:40:21.333+05:30	2026-06-23 17:04:03.53+05:30
65f9e9e4-e888-4006-b715-93117be319b9	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	alla ka msg sir	\N	\N	\N	\N	\N	\N	read	2026-06-23 17:04:03.53+05:30	\N	2026-06-23 16:40:55.282+05:30	2026-06-23 17:04:03.53+05:30
2c436853-addc-4e72-ac0d-44b13bbf7fa6	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	bola sir	\N	\N	\N	\N	\N	\N	read	2026-06-23 17:04:03.53+05:30	\N	2026-06-23 16:42:37.642+05:30	2026-06-23 17:04:03.53+05:30
756755d4-9200-4134-95ff-a9d79df0fdb7	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	ajj kutha	\N	\N	\N	\N	\N	\N	read	2026-06-23 17:04:03.53+05:30	\N	2026-06-23 16:42:41.571+05:30	2026-06-23 17:04:03.53+05:30
bd3bbc22-8bd9-4e63-8309-1abdde373854	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	sir chha alay	\N	\N	\N	\N	\N	\N	read	2026-06-23 17:04:03.53+05:30	\N	2026-06-23 17:02:51.699+05:30	2026-06-23 17:04:03.53+05:30
286cc4cc-4476-4fe9-b61d-638a4e00d526	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	hello	\N	\N	\N	\N	\N	\N	read	2026-06-23 17:04:03.53+05:30	\N	2026-06-23 17:02:57.778+05:30	2026-06-23 17:04:03.53+05:30
1cd92a23-0f97-4577-ae44-4349b6f562ac	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	sir	\N	\N	\N	\N	\N	\N	read	2026-06-23 17:04:03.53+05:30	\N	2026-06-23 17:02:59.043+05:30	2026-06-23 17:04:03.53+05:30
3e3db8e5-155d-41b4-b0cf-1ff7f1e78697	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	chahha alay	\N	\N	\N	\N	\N	\N	read	2026-06-23 17:04:03.53+05:30	\N	2026-06-23 17:03:08.16+05:30	2026-06-23 17:04:03.53+05:30
6282f7d7-fd7e-4adf-9858-cbda0c226364	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	chala	\N	\N	\N	\N	\N	\N	read	2026-06-23 17:04:03.53+05:30	\N	2026-06-23 17:03:20.329+05:30	2026-06-23 17:04:03.53+05:30
7c4c98d7-5bd2-47a0-b55d-7c753bfa4a26	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	baher	\N	\N	\N	\N	\N	\N	read	2026-06-23 17:04:03.53+05:30	\N	2026-06-23 17:03:22.05+05:30	2026-06-23 17:04:03.53+05:30
459a05f4-e03c-4996-a4db-7b76314fae4f	267213de-f682-432b-bb5c-77fd25dba68c	55d60813-00a5-4059-821f-8bf6da1d6262	text	ok chelo	\N	\N	\N	\N	\N	\N	read	2026-06-23 17:07:57.604+05:30	\N	2026-06-23 17:04:14.731+05:30	2026-06-23 17:07:57.605+05:30
da0880b2-30b6-4511-b2f6-7032f52356de	beeede8e-1524-4ee7-b8f2-81045b39c7f0	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	chal re	\N	\N	\N	\N	\N	\N	delivered	\N	\N	2026-06-23 17:08:02.797+05:30	2026-06-24 09:14:26.084+05:30
29ba4d30-fd29-421b-9a9d-fcc44d521708	beeede8e-1524-4ee7-b8f2-81045b39c7f0	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	pora	\N	\N	\N	\N	\N	\N	delivered	\N	\N	2026-06-23 17:08:04.522+05:30	2026-06-24 09:14:26.084+05:30
f208bf2f-792e-4933-ba1b-a1d03c0bb3a2	3dd1c0ae-9a6f-4e8b-81ec-be44de008c86	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	text	hi	\N	\N	\N	\N	\N	\N	read	2026-06-24 13:52:38.245+05:30	\N	2026-06-24 13:52:03.977+05:30	2026-06-24 13:52:38.245+05:30
a6a8cebd-5c1b-43b2-8dbd-472d4993ffc7	3dd1c0ae-9a6f-4e8b-81ec-be44de008c86	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	text	hello	\N	\N	\N	\N	\N	\N	read	2026-06-24 13:53:23.247+05:30	\N	2026-06-24 13:52:53.373+05:30	2026-06-24 13:53:23.247+05:30
99b56fa8-45a4-4fbf-87bc-73945f4e8974	4867a86e-5b35-454b-8ce2-ab44139b65ab	2bac9feb-8e54-44cd-9393-0f84e9b236be	icebreaker	Dance floor or VIP lounge?	\N	\N	\N	\N	\N	\N	read	2026-07-07 13:25:03.81+05:30	\N	2026-07-04 16:20:22.664+05:30	2026-07-07 13:25:03.81+05:30
2a20a0e9-0c21-4771-8e8d-059960ae18b6	e5d99a31-018c-4b52-b3d9-e2c7a922a47e	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	text	5	\N	\N	\N	\N	\N	\N	read	2026-07-07 19:26:34.525+05:30	\N	2026-07-01 17:43:07.687+05:30	2026-07-07 19:26:34.525+05:30
ac57c231-56cf-4577-9c39-bbc76718a4b4	ad103d48-d690-473c-8f05-4b75c849834d	55d60813-00a5-4059-821f-8bf6da1d6262	text	Hi	\N	\N	\N	\N	\N	\N	read	2026-07-01 17:37:26.317+05:30	\N	2026-07-01 17:36:20.551+05:30	2026-07-01 17:37:26.317+05:30
1c49d735-c581-456b-884e-ff7652f8ab57	ad103d48-d690-473c-8f05-4b75c849834d	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	text	hi	\N	\N	\N	\N	\N	\N	read	2026-07-01 17:37:32.007+05:30	\N	2026-07-01 17:37:31.915+05:30	2026-07-01 17:37:32.008+05:30
a5ba2b59-74d3-4bab-9a11-82b12e080678	ad103d48-d690-473c-8f05-4b75c849834d	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	text	hi	\N	\N	\N	\N	\N	\N	read	2026-07-01 17:37:38.561+05:30	\N	2026-07-01 17:37:38.409+05:30	2026-07-01 17:37:38.561+05:30
73709b5e-020f-446f-872a-6a4e0ff14696	ad103d48-d690-473c-8f05-4b75c849834d	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	text	hello	\N	\N	\N	\N	\N	\N	read	2026-07-01 17:37:42.286+05:30	\N	2026-07-01 17:37:42.244+05:30	2026-07-01 17:37:42.287+05:30
652d2dd2-4f3d-4c42-9535-aa791f7823c5	ad103d48-d690-473c-8f05-4b75c849834d	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	text	🙂	\N	\N	\N	\N	\N	\N	read	2026-07-01 17:37:49.774+05:30	\N	2026-07-01 17:37:49.609+05:30	2026-07-01 17:37:49.774+05:30
631beb32-4c5f-4c82-98b7-99f41cb290b1	ad103d48-d690-473c-8f05-4b75c849834d	55d60813-00a5-4059-821f-8bf6da1d6262	text	Hello	\N	\N	\N	\N	\N	\N	read	2026-07-01 17:37:54.179+05:30	\N	2026-07-01 17:37:54.128+05:30	2026-07-01 17:37:54.179+05:30
94f02238-a420-432b-8f98-f55c771a9871	ad103d48-d690-473c-8f05-4b75c849834d	55d60813-00a5-4059-821f-8bf6da1d6262	text	Test	\N	\N	\N	\N	\N	\N	read	2026-07-01 17:38:28.436+05:30	\N	2026-07-01 17:38:18.024+05:30	2026-07-01 17:38:28.436+05:30
adf7693f-672e-4e05-934e-ab72367796a3	ad103d48-d690-473c-8f05-4b75c849834d	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	text	test 1	\N	\N	\N	\N	\N	\N	read	2026-07-01 17:40:02.517+05:30	\N	2026-07-01 17:38:43.673+05:30	2026-07-01 17:40:02.517+05:30
c4ad5ee1-5738-40d6-b53e-27a371fa5bd3	e5d99a31-018c-4b52-b3d9-e2c7a922a47e	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	hello	\N	\N	\N	\N	\N	\N	read	2026-07-01 17:41:16.906+05:30	\N	2026-07-01 17:41:07.119+05:30	2026-07-01 17:41:16.906+05:30
5ce4e42f-4850-4366-86a7-38ebb2ca9007	e5d99a31-018c-4b52-b3d9-e2c7a922a47e	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	text	hello	\N	\N	\N	\N	\N	\N	read	2026-07-01 17:41:37.655+05:30	\N	2026-07-01 17:41:21.164+05:30	2026-07-01 17:41:37.655+05:30
54a3e363-b3bc-442e-8621-88bec25ac747	e5d99a31-018c-4b52-b3d9-e2c7a922a47e	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	1	\N	\N	\N	\N	\N	\N	read	2026-07-01 17:41:51.539+05:30	\N	2026-07-01 17:41:51.284+05:30	2026-07-01 17:41:51.539+05:30
0b45a531-1e28-466c-980f-ae0562e35a52	e5d99a31-018c-4b52-b3d9-e2c7a922a47e	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	2	\N	\N	\N	\N	\N	\N	read	2026-07-01 17:42:06.597+05:30	\N	2026-07-01 17:41:59.118+05:30	2026-07-01 17:42:06.597+05:30
cabc32d2-5fab-427d-adf8-88952550d705	e5d99a31-018c-4b52-b3d9-e2c7a922a47e	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	3	\N	\N	\N	\N	\N	\N	read	2026-07-01 17:43:02.277+05:30	\N	2026-07-01 17:42:10.144+05:30	2026-07-01 17:43:02.277+05:30
074b7c8a-7a11-418e-b479-2f7e6cedf789	e5d99a31-018c-4b52-b3d9-e2c7a922a47e	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	4	\N	\N	\N	\N	\N	\N	read	2026-07-01 17:43:02.277+05:30	\N	2026-07-01 17:42:42.404+05:30	2026-07-01 17:43:02.277+05:30
e1d94178-4201-4240-aff6-5d59b71b431a	267213de-f682-432b-bb5c-77fd25dba68c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	text	hello	\N	\N	\N	\N	\N	\N	read	2026-07-02 12:16:24.831+05:30	\N	2026-07-01 17:40:47.645+05:30	2026-07-02 12:16:24.831+05:30
ea98b320-c0eb-4425-8cf3-e4f3975c252e	4867a86e-5b35-454b-8ce2-ab44139b65ab	2bac9feb-8e54-44cd-9393-0f84e9b236be	text	Hi	\N	\N	\N	\N	\N	\N	read	2026-07-02 12:16:28.808+05:30	\N	2026-06-25 18:14:28.168+05:30	2026-07-02 12:16:28.808+05:30
93f64094-226e-489c-b2ad-05d1ad708ac4	4867a86e-5b35-454b-8ce2-ab44139b65ab	55d60813-00a5-4059-821f-8bf6da1d6262	text	hello	\N	\N	\N	\N	\N	\N	read	2026-07-04 10:54:04.939+05:30	\N	2026-07-04 10:54:04.89+05:30	2026-07-04 10:54:04.939+05:30
fbb0c233-c8a9-4687-8d11-8deab5924f94	4867a86e-5b35-454b-8ce2-ab44139b65ab	55d60813-00a5-4059-821f-8bf6da1d6262	text	check	\N	\N	\N	\N	\N	\N	read	2026-07-04 14:58:22.915+05:30	\N	2026-07-04 14:57:41.549+05:30	2026-07-04 14:58:22.916+05:30
a85825e7-bea6-4bff-b64e-e047e4189b92	4867a86e-5b35-454b-8ce2-ab44139b65ab	55d60813-00a5-4059-821f-8bf6da1d6262	text	hello check	\N	\N	\N	\N	\N	\N	read	2026-07-04 14:58:36.683+05:30	\N	2026-07-04 14:58:36.622+05:30	2026-07-04 14:58:36.683+05:30
\.


--
-- Data for Name: otp_verifications; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.otp_verifications (id, phone, otp_code, purpose, verified_at, expires_at, attempts, created_at) FROM stdin;
c9521e30-159d-459e-877a-8c2341b2d47e	8263946611	e523840da72451cfef9b26935e4ebc63be329cf094c7f2a020374d525e305b82	registration	2026-07-03 15:14:30.62+05:30	2026-07-03 15:19:24.359+05:30	0	2026-07-03 15:14:24.364+05:30
4b6d549e-6597-4df3-ada1-61647f5824b8	9542555356	b28bb581f28c6301ef37c4f38ca420fccc0ad1870a1d45ab748da876be7784c5	registration	2026-07-04 16:28:12.245+05:30	2026-07-04 16:32:46.321+05:30	1	2026-07-04 16:27:46.337+05:30
086a961f-ae18-4898-8bc7-7f6fe5387796	9067565606	168692e97e05a1e6c2449409042ade08655d5f6f273c492954a51e430c461ed4	registration	2026-06-25 12:15:18.622+05:30	2026-06-25 12:20:13.467+05:30	0	2026-06-25 12:15:13.476+05:30
d3d2ca20-8a40-4000-8d84-48b80cf66102	9542555356	a3d0c75739a3c6a80dcb6f9d71f9da29b49b62995801bc52957e06acb87db33d	registration	2026-07-04 16:29:13.449+05:30	2026-07-04 16:34:07.31+05:30	0	2026-07-04 16:29:07.32+05:30
29b344fe-cd94-4dd9-80ec-78714e4cd042	7040203283	298647699bcb31c22e6d6486891b637b28f1c3cf4d0cf710ce5ce775f9a1e4d3	registration	\N	2026-06-30 15:25:51.147+05:30	0	2026-06-30 15:20:51.153+05:30
4b256857-4c08-4bd8-9593-f16dd47ba8b4	9699320615	dab6e4672321db0bd8c3d5078217fc9c6dbaf4c763cb80ea111efbb39792abb2	registration	2026-06-30 15:22:07.399+05:30	2026-06-30 15:27:00.29+05:30	0	2026-06-30 15:22:00.292+05:30
3f16cecc-7be4-42e0-bace-383e55234d42	9699320615	ca306090974ef3723973a222ce2debdecfd0942bf70aa4bcc33dcdff3e8af26a	registration	2026-06-30 15:23:03.047+05:30	2026-06-30 15:27:56.865+05:30	0	2026-06-30 15:22:56.868+05:30
9b5f0db9-49e0-4fc7-ad3f-c624bcee482a	9699320615	bfa6b4fe534027ca73931fcbe394d8a59a002312b9f60d8759a85ec4e0b635c5	registration	2026-06-30 15:23:48.788+05:30	2026-06-30 15:28:42.354+05:30	0	2026-06-30 15:23:42.357+05:30
a887bbb9-9ca8-4e6b-bfc0-2a98b79400ed	9542555356	a8899f6ce1203a6f46ced13e009695d01c0feb473ce15b8cb9a95c8e47273819	registration	2026-07-04 16:33:30.167+05:30	2026-07-04 16:38:23.854+05:30	0	2026-07-04 16:33:23.864+05:30
4a93605d-cf0a-477f-b732-0ee6bd588489	9404042721	5492da8979de59f2a90187ab8402db6de1ad167faebf6597531b74ad66cf78fe	registration	2026-07-02 20:21:45.544+05:30	2026-07-02 20:26:29.216+05:30	0	2026-07-02 20:21:29.222+05:30
\.


--
-- Data for Name: party_plan_requests; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.party_plan_requests (id, plan_id, requester_id, status, joiner_payment_status, joiner_razorpay_order_id, joiner_razorpay_payment_id, payment_timeout_at, lat_lang_check_in, created_at, updated_at) FROM stdin;
7db1eaed-ea37-41e2-b6f4-d6e6408765f9	2eaf44f2-6880-471f-af27-d49b228ea5f8	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	payment_failed	unpaid	order_T2IEY4yvI9neB2	\N	2026-06-16 17:53:25.761+05:30	f	2026-06-16 17:22:34.616+05:30	2026-06-16 17:55:00.036+05:30
4d89362a-b60a-4a2d-9d84-8603a0c98401	5580d653-66ac-4c39-a33a-d1453142ec08	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	accepted	refunded	order_T2J5IQ0rL6W1Ho	pay_T2J5unWarekyM7	2026-06-16 18:43:22.083+05:30	f	2026-06-16 18:13:01.778+05:30	2026-06-16 18:14:06.946+05:30
687ab639-d8e6-4d56-aff1-4b63ac065043	66843a2e-cf6e-4223-9951-16a3eadb3347	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	pending	unpaid	\N	\N	\N	f	2026-06-29 14:27:55.709+05:30	2026-06-29 14:27:55.709+05:30
63723408-f013-4108-a245-3c29406fdf2d	194ba9f7-269c-4897-8564-932c3229d3bc	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	pending	unpaid	\N	\N	\N	f	2026-07-01 17:20:48.973+05:30	2026-07-01 17:20:48.973+05:30
dd278633-adbc-4179-8bee-2ac35d4da00c	2acbc8e2-1010-4c59-85cf-5680f95aecc0	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	rejected	unpaid	\N	\N	\N	f	2026-06-30 16:29:39.001+05:30	2026-07-01 17:21:46.629+05:30
1553e450-6efe-4f32-a6ec-496fd29470c8	2acbc8e2-1010-4c59-85cf-5680f95aecc0	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	rejected	unpaid	\N	\N	\N	f	2026-07-01 12:27:34.627+05:30	2026-07-01 17:21:46.629+05:30
06ca6ea5-ef88-4961-98fa-3a8029d250e1	2acbc8e2-1010-4c59-85cf-5680f95aecc0	55d60813-00a5-4059-821f-8bf6da1d6262	accepted	refunded	order_T8EDbksmf2eBKR	pay_T8EEG1gVmxsEL2	2026-07-01 17:51:46.616+05:30	f	2026-07-01 10:38:21.683+05:30	2026-07-01 17:23:39.851+05:30
6b42e9c6-682c-47fb-8d6d-9eaf060f0d87	194ba9f7-269c-4897-8564-932c3229d3bc	64786496-e9b0-4ecb-8285-3095ef3bcf16	pending	unpaid	\N	\N	\N	f	2026-07-02 12:25:38.788+05:30	2026-07-02 12:25:38.788+05:30
7e2f7b4e-29cc-4126-8ef9-2228ba79f7d5	194ba9f7-269c-4897-8564-932c3229d3bc	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	pending	unpaid	\N	\N	\N	f	2026-07-02 12:41:27.766+05:30	2026-07-02 12:41:27.766+05:30
7b82692b-981f-48a2-8940-28bd30d818e6	194ba9f7-269c-4897-8564-932c3229d3bc	dd2f25ca-d7e1-4670-a9c3-24478c9e8c3e	pending	unpaid	\N	\N	\N	f	2026-07-03 13:25:38.938+05:30	2026-07-03 13:25:38.938+05:30
51ebc0e9-f4f2-47ca-b45a-ac7d8d620b90	d10ffcb5-1894-4947-9ed9-283a15bb89c3	55d60813-00a5-4059-821f-8bf6da1d6262	payment_failed	unpaid	order_T904iN7yHEpvR1	\N	2026-07-03 16:40:39.058+05:30	f	2026-07-03 16:08:48.177+05:30	2026-07-03 16:45:00.04+05:30
ebc55b64-d4d6-4332-badd-91bffe2f40dd	ee6098f1-4a7c-4f46-9793-7a191e702322	55d60813-00a5-4059-821f-8bf6da1d6262	cancelled	unpaid	order_T9NaFAXFaWTwDW	\N	2026-07-04 15:40:26.566+05:30	f	2026-07-04 15:10:09.631+05:30	2026-07-04 15:19:08.224+05:30
11d0d63a-7c46-4a53-911f-138e5415e5e5	aca3aa57-f57c-4b4d-b2e5-51285c9c6337	2bac9feb-8e54-44cd-9393-0f84e9b236be	payment_failed	unpaid	order_TAXOV4lzXJHdpe	\N	2026-07-07 13:55:15.949+05:30	f	2026-07-07 13:07:11.966+05:30	2026-07-07 14:00:00.059+05:30
cf1296ec-2388-4c8f-b86c-ae02ddee4068	d10ffcb5-1894-4947-9ed9-283a15bb89c3	2bac9feb-8e54-44cd-9393-0f84e9b236be	payment_failed	unpaid	order_TAZ5xGNKoO3zgy	\N	2026-07-07 15:35:06.429+05:30	f	2026-07-07 11:56:28.779+05:30	2026-07-07 15:40:00.047+05:30
42bf674c-dcfa-4997-a51b-e7f3948c73e2	aca3aa57-f57c-4b4d-b2e5-51285c9c6337	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	payment_failed	unpaid	order_TAuh6ukWV88lq2	\N	2026-07-08 12:42:50.158+05:30	f	2026-07-08 11:37:27.859+05:30	2026-07-08 12:45:00.051+05:30
\.


--
-- Data for Name: party_plans; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.party_plans (id, user_id, venue_id, message, plan_date_time, status, visibility, selected_users, deposit_amount, host_payment_status, host_razorpay_order_id, host_razorpay_payment_id, is_live, expires_at, host_lat_lang_check_in, payment_status, created_at, updated_at, mobile_number, optional_mobile_number) FROM stdin;
ee6098f1-4a7c-4f46-9793-7a191e702322	2bac9feb-8e54-44cd-9393-0f84e9b236be	ab320228-2d2f-41da-9d07-c9f5a915211e	Let's party at Sash! 🚀	2026-07-04 15:02:00+05:30	cancelled	public	\N	99.00	paid	order_T9NaFFUdNRbLIc	pay_T9NczIOvgJyObG	f	2026-07-04 15:02:00+05:30	f	pending	2026-07-04 15:02:32.523+05:30	2026-07-04 15:19:08.219+05:30	\N	\N
194ba9f7-269c-4897-8564-932c3229d3bc	55d60813-00a5-4059-821f-8bf6da1d6262	4311111f-8e89-4016-a39c-faf3d12eacf9	Let's party at Echho! 🚀	2026-07-06 18:30:00+05:30	inactive	public	\N	99.00	unpaid	order_T8Dr2EjugALzxH	\N	t	2026-07-06 18:30:00+05:30	f	pending	2026-07-01 17:00:24.315+05:30	2026-07-07 11:25:00.049+05:30	\N	\N
5580d653-66ac-4c39-a33a-d1453142ec08	55d60813-00a5-4059-821f-8bf6da1d6262	17887092-ea6a-4102-82a0-06aefdb1d79d	Let's party at LOVA! 🚀	2026-06-18 18:12:00+05:30	inactive	public	\N	99.00	refunded	order_T2J5ISANbcSaGw	pay_T2J5VRcgrDxJkh	f	2026-06-18 18:12:00+05:30	f	pending	2026-06-16 18:12:11.092+05:30	2026-06-16 18:14:06.95+05:30	\N	\N
2eaf44f2-6880-471f-af27-d49b228ea5f8	55d60813-00a5-4059-821f-8bf6da1d6262	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	Let's party at TETTORICCA! 🚀	2026-06-17 17:21:00+05:30	inactive	public	\N	99.00	paid	order_T2IEY6upFJoqmD	mock_payment	t	2026-06-17 17:21:00+05:30	f	pending	2026-06-16 17:21:24.046+05:30	2026-06-17 20:25:00.067+05:30	\N	\N
22f69798-16ab-4bb6-89a4-911afdb90996	55d60813-00a5-4059-821f-8bf6da1d6262	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	Let's party at Tettoricca! 🚀	2026-06-22 19:30:00+05:30	inactive	public	\N	99.00	unpaid	order_T4fuWPFforBRvH	\N	t	2026-06-22 19:30:00+05:30	f	pending	2026-06-22 17:51:07.138+05:30	2026-06-23 11:25:00.143+05:30	\N	\N
810f15b6-7c73-492d-81b8-7ad8db5d90b7	444f8f5f-9c18-43fd-956a-b0e41a79292b	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	Let's party at Tettoricca! 🚀	2026-06-26 15:30:00+05:30	inactive	public	\N	99.00	unpaid	order_T6AKSdVY8xYdDP	\N	t	2026-06-26 15:30:00+05:30	f	pending	2026-06-26 12:15:28.939+05:30	2026-06-26 18:30:00.05+05:30	\N	\N
586fc52f-1974-47aa-96b3-84ad8dea3bfc	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	17887092-ea6a-4102-82a0-06aefdb1d79d	Let's party at LOVA! 🚀	2026-06-26 18:30:00+05:30	inactive	public	\N	99.00	unpaid	order_T6FKAUmVw7P5zs	\N	t	2026-06-26 18:30:00+05:30	f	pending	2026-06-26 17:08:40.849+05:30	2026-06-26 21:30:00.067+05:30	\N	\N
66843a2e-cf6e-4223-9951-16a3eadb3347	55d60813-00a5-4059-821f-8bf6da1d6262	4311111f-8e89-4016-a39c-faf3d12eacf9	Let's party at Echho! 🚀	2026-06-29 18:30:00+05:30	inactive	public	\N	99.00	unpaid	order_T7N53pHEsZvu0F	\N	t	2026-06-29 18:30:00+05:30	f	pending	2026-06-29 13:22:55.537+05:30	2026-06-29 21:30:00.051+05:30	\N	\N
2acbc8e2-1010-4c59-85cf-5680f95aecc0	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	b50d85dd-ef32-4753-9e53-159ac11d8046	Let's party at Cafe Vanabella! 🚀	2026-07-03 09:06:00+05:30	inactive	public	\N	99.00	refunded	order_T8EDbq1okK5a4v	pay_T8EFV4VYGLpCBr	f	2026-07-03 09:06:00+05:30	f	pending	2026-06-30 15:06:48.223+05:30	2026-07-01 17:23:39.855+05:30	\N	\N
9fc2612b-eec7-45a7-91ef-f8bc4e693e49	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	17887092-ea6a-4102-82a0-06aefdb1d79d	Let's party at LOVA! 🚀	2026-06-24 21:00:00+05:30	cancelled	public	\N	99.00	unpaid	order_T2eYU6WuCakS03	\N	f	2026-06-24 21:00:00+05:30	f	pending	2026-06-17 15:13:34.112+05:30	2026-07-01 17:31:24.08+05:30	\N	\N
a072fa46-4de3-4649-af7d-a49c6dfaf6bc	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	b50d85dd-ef32-4753-9e53-159ac11d8046	Let's party at Cafe Vanabella! 🚀	2026-07-02 06:30:00+05:30	inactive	public	\N	99.00	unpaid	order_T8VzrAoALss3SQ	\N	t	2026-07-02 06:30:00+05:30	f	pending	2026-07-02 10:45:13.992+05:30	2026-07-02 10:50:00.064+05:30	\N	\N
d10ffcb5-1894-4947-9ed9-283a15bb89c3	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	b50d85dd-ef32-4753-9e53-159ac11d8046	Let's party at Cafe Vanabella! 🚀	2026-07-07 17:00:00+05:30	inactive	public	\N	99.00	unpaid	order_TAZ5xLnaU9WxoZ	\N	t	2026-07-07 17:00:00+05:30	f	pending	2026-07-03 16:07:12.603+05:30	2026-07-07 20:00:00.046+05:30	\N	\N
aca3aa57-f57c-4b4d-b2e5-51285c9c6337	55d60813-00a5-4059-821f-8bf6da1d6262	ab320228-2d2f-41da-9d07-c9f5a915211e	Let's party at Sash! 🚀	2026-07-08 18:30:00+05:30	cancelled	public	\N	99.00	unpaid	order_TAuh73R7NMwKGx	\N	f	2026-07-08 18:30:00+05:30	f	pending	2026-07-07 12:24:43.08+05:30	2026-07-08 12:45:00.056+05:30	8123456787	
\.


--
-- Data for Name: password_reset_tokens; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.password_reset_tokens (id, user_id, token, expires_at, used_at, created_at) FROM stdin;
d876757c-da61-411a-a0ec-20902a85385c	ccb35417-49f8-474d-8d33-6f4e9d7738c0	868295f2c9ad1d87e7e02c29d6b196ff0f8e2157e2f4eec10013737cae0f6fe6	2026-06-16 15:50:42.822+05:30	\N	2026-06-16 15:35:42.864+05:30
\.


--
-- Data for Name: payments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payments (id, transaction_id, booking_id, user_id, group_member_id, amount, currency, payment_method, payment_gateway, gateway_response, status, failure_reason, refund_amount, refunded_at, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: plan_join_requests; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.plan_join_requests (id, plan_id, requester_id, status, payment_status, share_amount, transaction_id, paid_at, message, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: plans; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.plans (id, user_id, venue_id, plan_date, start_time, table_package, payment_option, total_amount, max_joiners, current_joiners, status, description, booking_id, host_payment_status, host_transaction_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: social_connections; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.social_connections (id, requester_id, receiver_id, status, connected_at, created_at) FROM stdin;
8f11f080-44ff-4507-99d1-7b546bbd226c	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	blocked	\N	2026-07-06 17:24:53.626+05:30
34a97bbf-8d7b-4a1f-ad01-8faf7756af10	2bac9feb-8e54-44cd-9393-0f84e9b236be	1aa75230-368e-4dc9-aaec-378904c1377b	blocked	\N	2026-07-07 18:41:58.053+05:30
\.


--
-- Data for Name: strangers_meet_joiners; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.strangers_meet_joiners (id, strangers_meet_request_id, user_id, payment_status, payment_amount, razorpay_order_id, razorpay_payment_id, razorpay_signature, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: strangers_meet_requests; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.strangers_meet_requests (id, user_id, venue_id, subject, tagline, event_date_time, number_of_persons, status, payment_amount, payment_status, admin_notes, ticket_id, created_at, updated_at, razorpay_order_id, razorpay_payment_id, razorpay_signature, mobile_number, alternate_mobile_number, charges_per_head, slots_filled) FROM stdin;
83948b28-3212-42d7-abce-276269eec3f3	55d60813-00a5-4059-821f-8bf6da1d6262	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	meet	meet	2026-06-19 18:16:00+05:30	22	approved	2500.00	paid	\N	LNR-MQGN415L-3K3I5	2026-06-16 18:16:37.717+05:30	2026-06-16 18:20:28.954+05:30	\N	\N	\N		\N	0.00	0
cdd54d06-97e4-4bf0-8306-b7a47c91c5cd	55d60813-00a5-4059-821f-8bf6da1d6262	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	test	test	2026-06-18 19:23:00+05:30	22	approved	1000.00	paid	\N	LNR-MQGPEIFJ-U3IEU	2026-06-16 19:23:40.105+05:30	2026-06-16 19:24:37.136+05:30	order_T2KIKZr2g5PLDG	pay_T2KISymS2bkqII	b71c126969ead89fbfadfd554852e2fd222e73c87dde930d9250940f384b5d8c		\N	0.00	0
02287da9-6a2b-4110-993c-40bde1e985da	1aa75230-368e-4dc9-aaec-378904c1377b	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	Test	Test	2026-06-24 18:30:00+05:30	22	approved	2200.00	unpaid	\N	\N	2026-06-23 14:41:38.328+05:30	2026-06-23 14:42:33.271+05:30	\N	\N	\N		\N	0.00	0
3805bbdd-3d02-4a88-b352-2f098b887d70	64786496-e9b0-4ecb-8285-3095ef3bcf16	4311111f-8e89-4016-a39c-faf3d12eacf9	Test Event	Test Tag	2026-07-01 18:30:00+05:30	22	approved	2000.00	paid	\N	LNR-MR1XH850-V4LBO	2026-07-01 15:49:05.773+05:30	2026-07-01 15:53:50.388+05:30	order_T8Ci8J7txMXOot	pay_T8CiRfjGdGLF9X	4d629575fba129921b55dd48d8e6a91324ef4b48b53a40fcac188d409f1fd0a6		\N	0.00	0
f6d9b462-eb2f-4eb8-826b-bddbdb4f8fb3	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	4311111f-8e89-4016-a39c-faf3d12eacf9	developers meet	for developer minds	2026-07-15 18:00:00+05:30	30	approved	2000.00	paid	test	LNR-MR1ZMV2I-QUIHG	2026-07-01 16:00:11.109+05:30	2026-07-01 16:54:12.619+05:30	order_T8Dk8cTm9RFRv9	pay_T8DkOc6ps3VoDJ	05fe9f9610622f28dc35c7030815ca55660ea4d420a339050b7de08f14fd0f47		\N	0.00	0
aa991c4c-9b48-4450-bba7-3aca8500df6e	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	ab320228-2d2f-41da-9d07-c9f5a915211e	Developers meet	For all dev minds	2026-07-10 21:00:00+05:30	30	approved	2500.00	unpaid	\N	\N	2026-07-03 14:58:52.669+05:30	2026-07-03 14:59:29.565+05:30	\N	\N	\N		\N	0.00	0
bd5d9727-80fc-4794-ad91-5cc0c074723d	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	a34456dc-fc25-4092-aae8-d3f8fd29d76f	For all guitarist	night for Strummers	2026-07-11 21:00:00+05:30	30	approved	3000.00	unpaid	\N	\N	2026-07-03 16:13:11.145+05:30	2026-07-03 16:30:15.695+05:30	\N	\N	\N		\N	0.00	0
\.


--
-- Data for Name: user_interests; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_interests (id, user_id, category, interest, proficiency_level, created_at) FROM stdin;
\.


--
-- Data for Name: user_matches; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_matches (id, user1_id, user2_id, compatibility_score, common_interests, match_reason, status, venue_id, event_date, expires_at, created_at) FROM stdin;
b5c4cbec-fbdf-4a4a-b682-e5f4fc6f83ea	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	75.00	\N	\N	pending	\N	\N	2026-07-13 17:22:59.347+05:30	2026-07-06 17:22:59.348+05:30
f4690b41-0338-48bc-aaf1-6247168f4b24	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	0.00	\N	\N	declined	\N	\N	2026-07-13 17:23:00.362+05:30	2026-07-06 17:23:00.363+05:30
0ad387ec-1d30-4eed-ac77-6a69b1fedc23	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	0.00	\N	\N	declined	\N	\N	2026-07-13 17:40:46.971+05:30	2026-07-06 17:40:46.972+05:30
f123f223-6ed6-424f-94a2-9a6a83ba1497	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	75.00	\N	\N	pending	\N	\N	2026-07-13 17:40:48.64+05:30	2026-07-06 17:40:48.64+05:30
96fa9fb6-576b-4410-8bbc-39ec1802f22a	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	75.00	\N	\N	pending	\N	\N	2026-07-13 17:59:12.292+05:30	2026-07-06 17:59:12.292+05:30
de7ae803-d039-4310-abfc-b438c17c7ba8	55d60813-00a5-4059-821f-8bf6da1d6262	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	75.00	\N	\N	pending	\N	\N	2026-07-13 18:00:19.784+05:30	2026-07-06 18:00:19.784+05:30
1d35414f-31df-4129-99b9-2226d4bd4e6e	71da26fc-a3a3-434a-aa6f-73220fd29fdd	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	95.00	\N	superlike	pending	\N	\N	2026-07-13 18:24:36.545+05:30	2026-07-06 18:24:36.545+05:30
556a04b7-62ae-49fc-9d91-69992438154a	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	55d60813-00a5-4059-821f-8bf6da1d6262	0.00	\N	\N	declined	\N	\N	2026-07-14 14:47:23.037+05:30	2026-07-07 14:47:23.038+05:30
735dead3-3b58-47b2-b458-0ab70df7b304	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	75.00	\N	\N	pending	\N	\N	2026-07-14 15:29:12.754+05:30	2026-07-07 15:29:12.755+05:30
847a55f6-0b8e-43e2-a3ee-9a690fd3433b	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	95.00	\N	superlike	pending	\N	\N	2026-07-14 15:29:14.704+05:30	2026-07-07 15:29:14.704+05:30
20c98ec7-401b-4252-8b37-6a87ccacd30e	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-14 15:29:19.048+05:30	2026-07-07 15:29:19.048+05:30
a8dc7b75-2ce5-4e27-9bfb-7068e178700e	55d60813-00a5-4059-821f-8bf6da1d6262	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	75.00	\N	\N	pending	\N	\N	2026-07-14 15:29:20.012+05:30	2026-07-07 15:29:20.012+05:30
36d49589-88aa-4419-bee4-4cd16547e775	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-14 15:29:49.154+05:30	2026-07-07 15:29:49.154+05:30
64076263-6954-4298-86a4-a078c7e35ea1	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	75.00	\N	\N	pending	\N	\N	2026-07-14 15:29:58.022+05:30	2026-07-07 15:29:58.023+05:30
21580a8c-a30f-4835-9c2c-69e90027f2f5	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-14 15:30:11.678+05:30	2026-07-07 15:30:11.679+05:30
ac42aca8-3f9e-4c04-b1e7-2ca55bc8b9ef	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-14 15:30:12.744+05:30	2026-07-07 15:30:12.744+05:30
f3fdc4b4-b69d-4a1f-942a-3cd5abf96df0	55d60813-00a5-4059-821f-8bf6da1d6262	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	75.00	\N	\N	pending	\N	\N	2026-07-14 15:30:51.295+05:30	2026-07-07 15:30:51.295+05:30
935ec25d-6c63-4619-85fa-1ba47e542a56	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	75.00	\N	\N	pending	\N	\N	2026-07-14 15:42:40.608+05:30	2026-07-07 15:42:40.609+05:30
87528944-3e49-4786-b303-110936c2d5f0	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	1aa75230-368e-4dc9-aaec-378904c1377b	0.00	\N	\N	declined	\N	\N	2026-07-14 15:42:41.567+05:30	2026-07-07 15:42:41.568+05:30
11d5c104-1dc4-49fa-b26b-53142b21976f	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	75.00	\N	\N	pending	\N	\N	2026-07-14 15:42:42.847+05:30	2026-07-07 15:42:42.847+05:30
aaa57786-5f24-4f95-83fc-8be6540b44f3	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-14 15:42:43.53+05:30	2026-07-07 15:42:43.531+05:30
d4e3fea3-615c-4a16-b782-777e46fcec09	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	0.00	\N	\N	declined	\N	\N	2026-07-14 15:42:44.031+05:30	2026-07-07 15:42:44.031+05:30
c41b21bc-84a0-4843-af35-8b16dde09141	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	1aa75230-368e-4dc9-aaec-378904c1377b	75.00	\N	\N	pending	\N	\N	2026-07-14 15:42:45.773+05:30	2026-07-07 15:42:45.774+05:30
e95474bd-f5bf-4569-8e0e-1f8551dedd37	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	0.00	\N	\N	declined	\N	\N	2026-07-14 15:42:46.735+05:30	2026-07-07 15:42:46.735+05:30
bbe52bf8-726d-4e20-b2cc-d11a84234f55	55d60813-00a5-4059-821f-8bf6da1d6262	400a3048-dba7-4d56-9d10-cb5d7c0f18a0	75.00	\N	\N	pending	\N	\N	2026-07-15 12:12:09.189+05:30	2026-07-08 12:12:09.19+05:30
13a84df6-4f23-42ea-ae57-20c2c6649dc3	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	75.00	\N	\N	pending	\N	\N	2026-07-15 17:42:53.962+05:30	2026-07-08 17:42:53.963+05:30
657433a3-70d2-4ccd-9725-93d2a7609703	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	6d861d92-f6c6-45f7-b444-7315a2685465	0.00	\N	\N	declined	\N	\N	2026-07-15 17:42:55.051+05:30	2026-07-08 17:42:55.051+05:30
c00238c3-52b5-4f0b-8dc2-6742b4edc8f9	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	095d1b94-1a8b-47c2-b912-c9031f0d9fcb	0.00	\N	\N	declined	\N	\N	2026-07-15 17:42:56.07+05:30	2026-07-08 17:42:56.07+05:30
b2735443-b8b0-45a0-8781-0b090b63505d	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-15 17:42:56.161+05:30	2026-07-08 17:42:56.161+05:30
f73fc8f9-9a91-43d4-b9f3-545a3ee49897	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	71da26fc-a3a3-434a-aa6f-73220fd29fdd	0.00	\N	\N	declined	\N	\N	2026-07-15 17:42:57.216+05:30	2026-07-08 17:42:57.216+05:30
8ea27d77-ed05-4ef7-a7d5-ab2dea961f5a	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	b5bf9672-2e0f-4616-838e-5f8591862855	75.00	\N	\N	pending	\N	\N	2026-07-15 17:42:57.872+05:30	2026-07-08 17:42:57.872+05:30
3c0cddea-b7a5-4e1e-9897-d0be614c07f4	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-15 17:42:57.889+05:30	2026-07-08 17:42:57.89+05:30
e72d25f5-4b48-48d3-8ff4-db2de0c0bf3b	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	e4bcd759-8b6d-4900-abd8-f11ebbc830a4	0.00	\N	\N	declined	\N	\N	2026-07-15 17:42:59.205+05:30	2026-07-08 17:42:59.205+05:30
b18d4693-d8e0-4d50-8496-ed72d43134d1	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	75.00	\N	\N	pending	\N	\N	2026-07-15 17:42:59.612+05:30	2026-07-08 17:42:59.613+05:30
38a4d90a-abc4-41a7-b9ed-253acadf4755	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	dd2f25ca-d7e1-4670-a9c3-24478c9e8c3e	75.00	\N	\N	pending	\N	\N	2026-07-15 17:43:00.765+05:30	2026-07-08 17:43:00.766+05:30
f32e2df6-c39e-4951-866e-755219d8cd9d	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	75.00	\N	\N	pending	\N	\N	2026-07-15 17:43:00.909+05:30	2026-07-08 17:43:00.91+05:30
aa3760ce-2fb3-41a9-b168-73a057afc308	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	7198fd2d-abfc-4ebb-b819-00ce75f493d2	0.00	\N	\N	declined	\N	\N	2026-07-15 17:43:01.191+05:30	2026-07-08 17:43:01.191+05:30
1e569f07-62e1-489f-8355-4b5825df60c8	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	37c1bb21-26d1-4082-a1da-871a16b0b232	0.00	\N	\N	declined	\N	\N	2026-07-15 17:43:01.779+05:30	2026-07-08 17:43:01.779+05:30
d3b0061a-2f34-416e-a37a-d528a641801d	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	75.00	\N	\N	pending	\N	\N	2026-07-15 17:43:02.261+05:30	2026-07-08 17:43:02.261+05:30
13d7b43a-0cbd-4aa5-9969-8de742fc513f	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	400a3048-dba7-4d56-9d10-cb5d7c0f18a0	0.00	\N	\N	declined	\N	\N	2026-07-15 17:43:02.728+05:30	2026-07-08 17:43:02.729+05:30
8e1cf93c-fe86-4535-80f8-78fd53afce43	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	326982fd-3909-4791-b8d4-66efbfaf2734	0.00	\N	\N	declined	\N	\N	2026-07-15 17:43:03.321+05:30	2026-07-08 17:43:03.322+05:30
f933cdf4-8593-4269-8411-62e49b23f663	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	75.00	\N	\N	pending	\N	\N	2026-07-15 17:43:04.034+05:30	2026-07-08 17:43:04.035+05:30
9629bd6a-cdfe-42f7-b589-c684c8f82967	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	64786496-e9b0-4ecb-8285-3095ef3bcf16	75.00	\N	\N	pending	\N	\N	2026-07-15 17:43:04.302+05:30	2026-07-08 17:43:04.302+05:30
1628eb70-597a-4139-9748-55bb89dad40c	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	6bdc7560-5b6c-4cb4-b72b-1666fddfa5f2	75.00	\N	\N	pending	\N	\N	2026-07-15 17:43:04.962+05:30	2026-07-08 17:43:04.962+05:30
e026c750-0f10-4154-9ec3-0b0ce15b005c	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	dd2efb63-a121-4f55-ac86-8c43da14fcef	75.00	\N	\N	pending	\N	\N	2026-07-15 17:43:05.671+05:30	2026-07-08 17:43:05.671+05:30
7d476cd6-8440-44dc-90fa-4279116c395a	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	6b5bd1f2-3d3f-4533-bfd2-61de0b21e299	0.00	\N	\N	declined	\N	\N	2026-07-15 17:43:07.554+05:30	2026-07-08 17:43:07.554+05:30
22350326-a428-486e-bc63-92e6ff11c347	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-15 17:43:08.349+05:30	2026-07-08 17:43:08.35+05:30
028fd9ce-d244-4015-ac95-d305154681e9	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	444f8f5f-9c18-43fd-956a-b0e41a79292b	0.00	\N	\N	declined	\N	\N	2026-07-15 17:43:08.543+05:30	2026-07-08 17:43:08.543+05:30
6156dc1f-b859-4e2e-ab03-b36687fc82d2	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	0.00	\N	\N	declined	\N	\N	2026-07-15 17:43:09.364+05:30	2026-07-08 17:43:09.364+05:30
b7e0c3c3-4639-4c84-bb4a-bf8f87687b5c	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-15 17:43:09.825+05:30	2026-07-08 17:43:09.826+05:30
322e6c76-4f9c-4b2e-8c6b-c21d04139f7e	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	6d861d92-f6c6-45f7-b444-7315a2685465	75.00	\N	\N	pending	\N	\N	2026-07-15 17:43:11.135+05:30	2026-07-08 17:43:11.136+05:30
7bd13cee-88a0-4a75-a75e-9c1e0e7de401	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-15 17:43:11.567+05:30	2026-07-08 17:43:11.567+05:30
5436e8d3-16d7-48ec-b10d-b4c7e941bc0d	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	095d1b94-1a8b-47c2-b912-c9031f0d9fcb	75.00	\N	\N	pending	\N	\N	2026-07-15 17:43:11.619+05:30	2026-07-08 17:43:11.619+05:30
9a4ded2c-1d81-4358-8cd9-2d2c1888a1e9	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	75.00	\N	\N	pending	\N	\N	2026-07-15 17:43:13.527+05:30	2026-07-08 17:43:13.527+05:30
b0873d84-b84c-4186-9b79-1c79c3b4dd6a	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-15 17:43:18.137+05:30	2026-07-08 17:43:18.137+05:30
fa8a5b54-98a3-4aec-80cd-9b759e45a817	55d60813-00a5-4059-821f-8bf6da1d6262	6d861d92-f6c6-45f7-b444-7315a2685465	75.00	\N	\N	pending	\N	\N	2026-07-15 17:46:17.549+05:30	2026-07-08 17:46:17.549+05:30
bdfec770-4108-4f5d-a936-9ac433b7110a	55d60813-00a5-4059-821f-8bf6da1d6262	6d861d92-f6c6-45f7-b444-7315a2685465	75.00	\N	\N	pending	\N	\N	2026-07-15 17:46:34.637+05:30	2026-07-08 17:46:34.637+05:30
5416e160-dab9-4a4b-aeef-d96425e52bca	55d60813-00a5-4059-821f-8bf6da1d6262	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	75.00	\N	\N	pending	\N	\N	2026-07-16 11:35:05.423+05:30	2026-07-09 11:35:05.425+05:30
8776b0fa-6f37-4021-88f0-7d3d47f34451	55d60813-00a5-4059-821f-8bf6da1d6262	1aa75230-368e-4dc9-aaec-378904c1377b	0.00	\N	\N	declined	\N	\N	2026-07-16 11:35:14.222+05:30	2026-07-09 11:35:14.222+05:30
90b1dc0e-580f-4806-b53f-7ecbcea917dc	55d60813-00a5-4059-821f-8bf6da1d6262	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	0.00	\N	\N	declined	\N	\N	2026-07-16 11:35:22.212+05:30	2026-07-09 11:35:22.212+05:30
1c2005e8-a6b1-4814-acc9-a58d68edaabe	55d60813-00a5-4059-821f-8bf6da1d6262	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	0.00	\N	\N	declined	\N	\N	2026-07-16 11:46:43.304+05:30	2026-07-09 11:46:43.305+05:30
ab4f458d-717b-45a2-bbd0-523599ff2e9f	55d60813-00a5-4059-821f-8bf6da1d6262	1aa75230-368e-4dc9-aaec-378904c1377b	0.00	\N	\N	declined	\N	\N	2026-07-16 11:46:45.401+05:30	2026-07-09 11:46:45.402+05:30
f9287a84-5b93-431f-a809-393d1fdff726	55d60813-00a5-4059-821f-8bf6da1d6262	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	0.00	\N	\N	declined	\N	\N	2026-07-16 11:46:47.202+05:30	2026-07-09 11:46:47.202+05:30
4b3f1aba-3e14-44b0-9c82-ebb1e4e8652d	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-16 11:46:48.853+05:30	2026-07-09 11:46:48.853+05:30
d6ca83ff-4caf-4c56-a309-d9618dd09be5	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	75.00	\N	\N	pending	\N	\N	2026-07-16 11:46:59.133+05:30	2026-07-09 11:46:59.133+05:30
fadb43d7-586a-4315-b99a-cdd89992a495	55d60813-00a5-4059-821f-8bf6da1d6262	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	75.00	\N	\N	pending	\N	\N	2026-07-16 11:47:01.237+05:30	2026-07-09 11:47:01.237+05:30
de42e4ee-8b8c-495f-bc79-bc7d964ed2f3	55d60813-00a5-4059-821f-8bf6da1d6262	1aa75230-368e-4dc9-aaec-378904c1377b	75.00	\N	\N	pending	\N	\N	2026-07-16 11:47:03.583+05:30	2026-07-09 11:47:03.583+05:30
62635fe0-5ccd-4670-9f3a-93428904d4d5	55d60813-00a5-4059-821f-8bf6da1d6262	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	0.00	\N	\N	declined	\N	\N	2026-07-16 11:47:08.514+05:30	2026-07-09 11:47:08.514+05:30
2cc41b25-91fc-4cd0-82b5-86aef1bf76e8	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-16 11:47:30.656+05:30	2026-07-09 11:47:30.656+05:30
1207c260-3670-4527-bb41-a9c8b387d61a	55d60813-00a5-4059-821f-8bf6da1d6262	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	0.00	\N	\N	declined	\N	\N	2026-07-16 11:47:37.861+05:30	2026-07-09 11:47:37.861+05:30
73924146-17a5-4e00-bb1f-26bee7f409a5	1aa75230-368e-4dc9-aaec-378904c1377b	6d861d92-f6c6-45f7-b444-7315a2685465	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:28.344+05:30	2026-07-09 12:00:28.344+05:30
3fe6d31f-3050-43a9-aea1-b3bbf11200e9	1aa75230-368e-4dc9-aaec-378904c1377b	095d1b94-1a8b-47c2-b912-c9031f0d9fcb	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:30.051+05:30	2026-07-09 12:00:30.052+05:30
dc7862bb-efee-4899-90b4-c9f367457ba6	1aa75230-368e-4dc9-aaec-378904c1377b	71da26fc-a3a3-434a-aa6f-73220fd29fdd	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:31.608+05:30	2026-07-09 12:00:31.608+05:30
65eba27d-d942-45fb-b650-03c3e6950450	1aa75230-368e-4dc9-aaec-378904c1377b	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:33.198+05:30	2026-07-09 12:00:33.198+05:30
35ba70ac-46d0-4ed4-96d4-5b141250e2d7	1aa75230-368e-4dc9-aaec-378904c1377b	b5bf9672-2e0f-4616-838e-5f8591862855	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:34.878+05:30	2026-07-09 12:00:34.878+05:30
901af543-b191-4e3c-bb16-ff998dbbf113	1aa75230-368e-4dc9-aaec-378904c1377b	dd2f25ca-d7e1-4670-a9c3-24478c9e8c3e	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:38.101+05:30	2026-07-09 12:00:38.102+05:30
1bbb560d-2f92-4644-a4cd-ede013626406	1aa75230-368e-4dc9-aaec-378904c1377b	7198fd2d-abfc-4ebb-b819-00ce75f493d2	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:39.622+05:30	2026-07-09 12:00:39.622+05:30
e6efb53d-5326-436a-9e1e-2476be89cfc3	1aa75230-368e-4dc9-aaec-378904c1377b	37c1bb21-26d1-4082-a1da-871a16b0b232	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:41.195+05:30	2026-07-09 12:00:41.195+05:30
a53566a2-be45-423a-b059-3b0eb278afe8	1aa75230-368e-4dc9-aaec-378904c1377b	326982fd-3909-4791-b8d4-66efbfaf2734	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:46.188+05:30	2026-07-09 12:00:46.189+05:30
61b17298-5484-4af1-a156-f7449d2d5a0d	1aa75230-368e-4dc9-aaec-378904c1377b	64786496-e9b0-4ecb-8285-3095ef3bcf16	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:47.855+05:30	2026-07-09 12:00:47.855+05:30
e7d50420-1b6e-4d38-8094-147ce80fb28e	1aa75230-368e-4dc9-aaec-378904c1377b	6bdc7560-5b6c-4cb4-b72b-1666fddfa5f2	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:49.407+05:30	2026-07-09 12:00:49.407+05:30
a1e28b41-2c3c-478a-b49a-6e4d87a479c1	1aa75230-368e-4dc9-aaec-378904c1377b	dd2efb63-a121-4f55-ac86-8c43da14fcef	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:51.158+05:30	2026-07-09 12:00:51.158+05:30
baefca1c-138c-4d7b-9a68-7761d151aa16	1aa75230-368e-4dc9-aaec-378904c1377b	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:52.849+05:30	2026-07-09 12:00:52.849+05:30
95b030d5-deba-4843-bd0d-05b8913e50ed	1aa75230-368e-4dc9-aaec-378904c1377b	6b5bd1f2-3d3f-4533-bfd2-61de0b21e299	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:54.46+05:30	2026-07-09 12:00:54.461+05:30
23211140-30ea-4d23-84ed-c453c34c9ab6	1aa75230-368e-4dc9-aaec-378904c1377b	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:57.486+05:30	2026-07-09 12:00:57.487+05:30
7fcc5114-c2dd-42eb-908f-e32a279a30fe	1aa75230-368e-4dc9-aaec-378904c1377b	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:59.109+05:30	2026-07-09 12:00:59.11+05:30
79f80c0b-cd81-4dfb-bdbc-a114748fa371	1aa75230-368e-4dc9-aaec-378904c1377b	e4bcd759-8b6d-4900-abd8-f11ebbc830a4	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:36.56+05:30	2026-07-09 12:00:36.56+05:30
dce6c5a3-ec69-424f-89ed-cf0e38e8a14c	1aa75230-368e-4dc9-aaec-378904c1377b	400a3048-dba7-4d56-9d10-cb5d7c0f18a0	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:42.792+05:30	2026-07-09 12:00:42.792+05:30
f19ed464-e377-41ab-af8f-3de9646c4d6f	1aa75230-368e-4dc9-aaec-378904c1377b	444f8f5f-9c18-43fd-956a-b0e41a79292b	0.00	\N	\N	declined	\N	\N	2026-07-16 12:00:56.073+05:30	2026-07-09 12:00:56.073+05:30
9efb8c43-2e73-44f8-a54b-0792d4e50c8e	55d60813-00a5-4059-821f-8bf6da1d6262	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	0.00	\N	\N	declined	\N	\N	2026-07-16 12:33:38.219+05:30	2026-07-09 12:33:38.22+05:30
3edff087-9b45-4773-bd0f-c42a15ea8c13	55d60813-00a5-4059-821f-8bf6da1d6262	b5bf9672-2e0f-4616-838e-5f8591862855	0.00	\N	\N	declined	\N	\N	2026-07-16 12:33:41.308+05:30	2026-07-09 12:33:41.308+05:30
1146415e-1999-4f36-9672-16bfecd2feef	55d60813-00a5-4059-821f-8bf6da1d6262	e4bcd759-8b6d-4900-abd8-f11ebbc830a4	0.00	\N	\N	declined	\N	\N	2026-07-16 12:33:42.929+05:30	2026-07-09 12:33:42.93+05:30
15cedc45-ac1f-4652-b109-ea1ae3d6140f	55d60813-00a5-4059-821f-8bf6da1d6262	dd2f25ca-d7e1-4670-a9c3-24478c9e8c3e	0.00	\N	\N	declined	\N	\N	2026-07-16 12:33:44.423+05:30	2026-07-09 12:33:44.423+05:30
7aa4ee02-e970-4627-8ff2-ab79e193dff1	55d60813-00a5-4059-821f-8bf6da1d6262	7198fd2d-abfc-4ebb-b819-00ce75f493d2	0.00	\N	\N	declined	\N	\N	2026-07-16 12:33:46.139+05:30	2026-07-09 12:33:46.14+05:30
d860230e-6ffd-4723-bfa4-d6360f445b3b	55d60813-00a5-4059-821f-8bf6da1d6262	37c1bb21-26d1-4082-a1da-871a16b0b232	0.00	\N	\N	declined	\N	\N	2026-07-16 12:33:47.605+05:30	2026-07-09 12:33:47.606+05:30
d94f39a8-a4fb-458f-85ff-adca21049aa7	55d60813-00a5-4059-821f-8bf6da1d6262	400a3048-dba7-4d56-9d10-cb5d7c0f18a0	0.00	\N	\N	declined	\N	\N	2026-07-16 12:33:48.987+05:30	2026-07-09 12:33:48.987+05:30
8b3d79c5-f68b-4178-87b0-7827304b2566	55d60813-00a5-4059-821f-8bf6da1d6262	326982fd-3909-4791-b8d4-66efbfaf2734	75.00	\N	\N	pending	\N	\N	2026-07-16 12:34:02.182+05:30	2026-07-09 12:34:02.183+05:30
a7e3dba4-61cc-491e-a271-18f78e48046d	55d60813-00a5-4059-821f-8bf6da1d6262	64786496-e9b0-4ecb-8285-3095ef3bcf16	75.00	\N	\N	pending	\N	\N	2026-07-16 12:34:03.915+05:30	2026-07-09 12:34:03.916+05:30
b420ce5c-a414-42cd-ba4d-b425794353d1	55d60813-00a5-4059-821f-8bf6da1d6262	6bdc7560-5b6c-4cb4-b72b-1666fddfa5f2	0.00	\N	\N	declined	\N	\N	2026-07-16 12:34:05.266+05:30	2026-07-09 12:34:05.267+05:30
21bc348d-0bd1-4648-98c1-00f6637c7aed	55d60813-00a5-4059-821f-8bf6da1d6262	dd2efb63-a121-4f55-ac86-8c43da14fcef	0.00	\N	\N	declined	\N	\N	2026-07-16 12:34:06.499+05:30	2026-07-09 12:34:06.499+05:30
aa4ee031-5df2-470a-961b-2f192c94a34f	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-16 12:34:07.863+05:30	2026-07-09 12:34:07.864+05:30
644798f9-39b7-415c-91bd-e607ba9929ed	55d60813-00a5-4059-821f-8bf6da1d6262	2bac9feb-8e54-44cd-9393-0f84e9b236be	75.00	\N	\N	pending	\N	\N	2026-07-16 12:34:09.562+05:30	2026-07-09 12:34:09.562+05:30
2d7d6252-b8d2-489a-a100-3d78b9fbbc3a	55d60813-00a5-4059-821f-8bf6da1d6262	6b5bd1f2-3d3f-4533-bfd2-61de0b21e299	75.00	\N	\N	pending	\N	\N	2026-07-16 12:34:10.876+05:30	2026-07-09 12:34:10.876+05:30
dced1746-1b3d-4fb3-9a57-5c798d3484cc	55d60813-00a5-4059-821f-8bf6da1d6262	444f8f5f-9c18-43fd-956a-b0e41a79292b	75.00	\N	\N	pending	\N	\N	2026-07-16 12:34:12.082+05:30	2026-07-09 12:34:12.082+05:30
c797ed82-131e-4596-a8eb-85cf4bce63ee	55d60813-00a5-4059-821f-8bf6da1d6262	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	75.00	\N	\N	pending	\N	\N	2026-07-16 12:34:13.318+05:30	2026-07-09 12:34:13.318+05:30
be1d83b0-7bd9-4c05-9017-10db34fccf61	55d60813-00a5-4059-821f-8bf6da1d6262	1aa75230-368e-4dc9-aaec-378904c1377b	75.00	\N	\N	pending	\N	\N	2026-07-16 12:34:14.484+05:30	2026-07-09 12:34:14.485+05:30
f0f00995-a8db-4e91-82a0-3ed25ae75996	55d60813-00a5-4059-821f-8bf6da1d6262	6d861d92-f6c6-45f7-b444-7315a2685465	75.00	\N	\N	pending	\N	\N	2026-07-16 12:34:15.707+05:30	2026-07-09 12:34:15.708+05:30
7aa81a88-a2c5-46e4-8431-3fe285ebe05f	55d60813-00a5-4059-821f-8bf6da1d6262	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	0.00	\N	\N	declined	\N	\N	2026-07-16 12:51:01.955+05:30	2026-07-09 12:51:01.956+05:30
1b847d2b-cd04-4c64-8202-25bac8abbadf	55d60813-00a5-4059-821f-8bf6da1d6262	b5bf9672-2e0f-4616-838e-5f8591862855	0.00	\N	\N	declined	\N	\N	2026-07-16 12:51:03.498+05:30	2026-07-09 12:51:03.498+05:30
1452bc1d-6a9c-4d84-a574-eea8a0e2f4e9	55d60813-00a5-4059-821f-8bf6da1d6262	e4bcd759-8b6d-4900-abd8-f11ebbc830a4	0.00	\N	\N	declined	\N	\N	2026-07-16 12:51:05.101+05:30	2026-07-09 12:51:05.101+05:30
489b14d7-14f5-4fa0-a023-d09a0781326d	55d60813-00a5-4059-821f-8bf6da1d6262	dd2f25ca-d7e1-4670-a9c3-24478c9e8c3e	0.00	\N	\N	declined	\N	\N	2026-07-16 12:51:06.661+05:30	2026-07-09 12:51:06.661+05:30
8c60c038-f801-4797-84c7-0ac41f80fe97	55d60813-00a5-4059-821f-8bf6da1d6262	7198fd2d-abfc-4ebb-b819-00ce75f493d2	0.00	\N	\N	declined	\N	\N	2026-07-16 12:51:08.171+05:30	2026-07-09 12:51:08.172+05:30
f81a94f4-509b-4d9e-aeeb-d1cbe4d169fc	55d60813-00a5-4059-821f-8bf6da1d6262	37c1bb21-26d1-4082-a1da-871a16b0b232	0.00	\N	\N	declined	\N	\N	2026-07-16 12:51:09.491+05:30	2026-07-09 12:51:09.491+05:30
33dfb228-ccd3-4621-a482-f522164df5b0	55d60813-00a5-4059-821f-8bf6da1d6262	400a3048-dba7-4d56-9d10-cb5d7c0f18a0	0.00	\N	\N	declined	\N	\N	2026-07-16 12:51:10.981+05:30	2026-07-09 12:51:10.981+05:30
3260eeb7-e159-472a-9989-a828bff03ef3	55d60813-00a5-4059-821f-8bf6da1d6262	326982fd-3909-4791-b8d4-66efbfaf2734	0.00	\N	\N	declined	\N	\N	2026-07-16 12:51:12.55+05:30	2026-07-09 12:51:12.55+05:30
d57c7df3-eac9-4fa6-8843-011dbf33b54f	55d60813-00a5-4059-821f-8bf6da1d6262	64786496-e9b0-4ecb-8285-3095ef3bcf16	0.00	\N	\N	declined	\N	\N	2026-07-16 12:51:14.365+05:30	2026-07-09 12:51:14.365+05:30
165d64ef-5090-4d2b-b542-8faec3196c08	55d60813-00a5-4059-821f-8bf6da1d6262	6bdc7560-5b6c-4cb4-b72b-1666fddfa5f2	0.00	\N	\N	declined	\N	\N	2026-07-16 12:51:15.713+05:30	2026-07-09 12:51:15.713+05:30
de91e86c-f19b-46d3-822c-da9faaf649f0	55d60813-00a5-4059-821f-8bf6da1d6262	dd2efb63-a121-4f55-ac86-8c43da14fcef	0.00	\N	\N	declined	\N	\N	2026-07-16 12:51:17.145+05:30	2026-07-09 12:51:17.146+05:30
e78e6f04-109c-49cc-8130-80acef483957	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	75.00	\N	\N	pending	\N	\N	2026-07-16 12:51:31.547+05:30	2026-07-09 12:51:31.547+05:30
e8df8a6f-6cfb-4d3e-8b46-4212b51c2578	55d60813-00a5-4059-821f-8bf6da1d6262	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	0.00	\N	\N	declined	\N	\N	2026-07-16 13:05:47.425+05:30	2026-07-09 13:05:47.425+05:30
2df7d23d-aead-4879-902d-d2d91d0e1f58	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-16 13:05:49.159+05:30	2026-07-09 13:05:49.159+05:30
a2bfba91-2bba-44aa-b165-f0a8ba39ac3f	55d60813-00a5-4059-821f-8bf6da1d6262	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	75.00	\N	\N	pending	\N	\N	2026-07-16 13:05:50.793+05:30	2026-07-09 13:05:50.794+05:30
5279405b-1e20-4a97-b6ea-1be420c37184	55d60813-00a5-4059-821f-8bf6da1d6262	1aa75230-368e-4dc9-aaec-378904c1377b	75.00	\N	\N	pending	\N	\N	2026-07-16 13:05:52.064+05:30	2026-07-09 13:05:52.064+05:30
4454e811-9178-4f02-ab0b-9bf1cf8804ba	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	0.00	\N	\N	declined	\N	\N	2026-07-16 13:05:56.077+05:30	2026-07-09 13:05:56.077+05:30
86971edf-b399-433d-a4d2-ac19926dadae	55d60813-00a5-4059-821f-8bf6da1d6262	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	0.00	\N	\N	declined	\N	\N	2026-07-16 13:05:57.415+05:30	2026-07-09 13:05:57.415+05:30
f29f43ff-91f9-4ca5-8cbb-49f8ec744f13	55d60813-00a5-4059-821f-8bf6da1d6262	1aa75230-368e-4dc9-aaec-378904c1377b	0.00	\N	\N	declined	\N	\N	2026-07-16 13:05:58.643+05:30	2026-07-09 13:05:58.643+05:30
600abd9d-ba51-41ef-842c-84b78bb6575a	55d60813-00a5-4059-821f-8bf6da1d6262	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	0.00	\N	\N	declined	\N	\N	2026-07-16 13:05:59.805+05:30	2026-07-09 13:05:59.805+05:30
fb780600-3e36-4417-b15c-293a962fc6d6	55d60813-00a5-4059-821f-8bf6da1d6262	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	75.00	\N	\N	pending	\N	\N	2026-07-16 13:06:03.754+05:30	2026-07-09 13:06:03.754+05:30
a222714e-c126-4611-8be4-c9c4b7ddff45	55d60813-00a5-4059-821f-8bf6da1d6262	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	75.00	\N	\N	pending	\N	\N	2026-07-16 13:06:05.039+05:30	2026-07-09 13:06:05.04+05:30
0201cc6a-2f05-435b-bfc5-92d574768d31	55d60813-00a5-4059-821f-8bf6da1d6262	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	75.00	\N	\N	pending	\N	\N	2026-07-16 13:06:06.317+05:30	2026-07-09 13:06:06.317+05:30
82daa656-6373-4a42-805c-28c9677f1791	55d60813-00a5-4059-821f-8bf6da1d6262	1aa75230-368e-4dc9-aaec-378904c1377b	75.00	\N	\N	pending	\N	\N	2026-07-16 13:06:07.417+05:30	2026-07-09 13:06:07.417+05:30
\.


--
-- Data for Name: user_penalties; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_penalties (id, user_id, plan_id, reason, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: user_photos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_photos (id, user_id, file_path, file_size, mime_type, is_primary, display_order, uploaded_at, created_at) FROM stdin;
64c5453b-c75c-4b29-acb3-985fb54e872c	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	uploads/users/7bcb98f3-632e-44e8-8cfc-ec9a2f63011e/gallery/1781605821494_8756cbfe69fc878d.jpg	81333	image/jpeg	t	0	2026-06-16 16:00:21.604+05:30	2026-06-16 16:00:21.606+05:30
62307645-d293-4267-8512-05bd297d7110	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	uploads/users/7bcb98f3-632e-44e8-8cfc-ec9a2f63011e/gallery/1781605821615_11c85ba8de9f0623.jpg	76354	image/jpeg	f	1	2026-06-16 16:00:21.716+05:30	2026-06-16 16:00:21.716+05:30
b4cb56b1-1386-4aba-988e-14ab30af0808	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	uploads/users/d124b298-6374-43bb-b7a4-2c3f1ba1bd84/gallery/1781615009104_40131893e9921b00.jpg	56865	image/jpeg	t	0	2026-06-16 18:33:29.2+05:30	2026-06-16 18:33:29.201+05:30
9d941efd-ecbe-4485-ac36-3707b703299a	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	uploads/users/d124b298-6374-43bb-b7a4-2c3f1ba1bd84/gallery/1781615009207_1b533ef086b20c69.jpg	144033	image/jpeg	f	1	2026-06-16 18:33:29.325+05:30	2026-06-16 18:33:29.325+05:30
22e19ab4-3d74-4fa7-9829-009be3970734	1aa75230-368e-4dc9-aaec-378904c1377b	uploads/users/1aa75230-368e-4dc9-aaec-378904c1377b/gallery/1782205708777_6cddc14f4d89dc1f.jpg	21547	image/jpeg	t	0	2026-06-23 14:38:28.85+05:30	2026-06-23 14:38:28.851+05:30
0b04fdf8-be3c-4d38-b09d-aa7f5efeab04	1aa75230-368e-4dc9-aaec-378904c1377b	uploads/users/1aa75230-368e-4dc9-aaec-378904c1377b/gallery/1782205708859_70da0c9a6c02f028.jpg	16839	image/jpeg	f	1	2026-06-23 14:38:28.908+05:30	2026-06-23 14:38:28.908+05:30
03a69ccc-64aa-47b0-be63-16e2f6de43f2	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	uploads/users/c45a3c3d-1032-417d-841d-fe5af2dcb0f7/gallery/1782206399856_21a7b239347a7185.jpg	40498	image/jpeg	t	0	2026-06-23 14:49:59.916+05:30	2026-06-23 14:49:59.916+05:30
39bf209f-c2e9-4f7e-8f5a-e30aa181668f	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	uploads/users/c45a3c3d-1032-417d-841d-fe5af2dcb0f7/gallery/1782206399923_aafacef358f30c4a.jpg	18551	image/jpeg	f	1	2026-06-23 14:49:59.976+05:30	2026-06-23 14:49:59.976+05:30
6d2920ee-01e0-4efe-82ab-038098c3d8e7	1aa75230-368e-4dc9-aaec-378904c1377b	uploads/users/1aa75230-368e-4dc9-aaec-378904c1377b/gallery/1782206748039_dc8d3be26f9e5535.jpg	35072	image/jpeg	t	0	2026-06-23 14:55:48.1+05:30	2026-06-23 14:55:48.1+05:30
06f7709a-a2b8-40ad-8bca-855f7a1429ef	1aa75230-368e-4dc9-aaec-378904c1377b	uploads/users/1aa75230-368e-4dc9-aaec-378904c1377b/gallery/1782206748108_b48aa4a2da5d1e13.jpg	15642	image/jpeg	f	1	2026-06-23 14:55:48.155+05:30	2026-06-23 14:55:48.155+05:30
32a63b56-c1a8-464a-8a72-96dfa1cdf1b7	1aa75230-368e-4dc9-aaec-378904c1377b	uploads/users/1aa75230-368e-4dc9-aaec-378904c1377b/gallery/1782206748160_8b0f4a9fa137bff9.jpg	20044	image/jpeg	f	2	2026-06-23 14:55:48.206+05:30	2026-06-23 14:55:48.206+05:30
f50b8509-9502-4a02-8a51-5437948007f8	444f8f5f-9c18-43fd-956a-b0e41a79292b	uploads/users/444f8f5f-9c18-43fd-956a-b0e41a79292b/gallery/1782209723890_4274c09b67066bc2.jpg	53281	image/jpeg	t	0	2026-06-23 15:45:24.024+05:30	2026-06-23 15:45:24.024+05:30
33e3b548-3268-4fc8-9e2e-d6761279b3cd	444f8f5f-9c18-43fd-956a-b0e41a79292b	uploads/users/444f8f5f-9c18-43fd-956a-b0e41a79292b/gallery/1782209724030_d26aeb522c16d447.jpg	133713	image/jpeg	f	1	2026-06-23 15:45:24.145+05:30	2026-06-23 15:45:24.145+05:30
4b8d7a63-685b-415b-81fa-ec89944e4157	2bac9feb-8e54-44cd-9393-0f84e9b236be	uploads/users/2bac9feb-8e54-44cd-9393-0f84e9b236be/gallery/1782382557151_c6de85e4d6097dd4.jpg	21438	image/jpeg	f	1	2026-06-25 15:45:57.187+05:30	2026-06-25 15:45:57.187+05:30
06afa781-d6bf-4068-901e-846755f134ee	2bac9feb-8e54-44cd-9393-0f84e9b236be	uploads/users/2bac9feb-8e54-44cd-9393-0f84e9b236be/gallery/1782382718827_4e40254101f34cb6.jpg	49656	image/jpeg	t	0	2026-06-25 15:48:38.896+05:30	2026-06-25 15:48:38.896+05:30
e8496f91-504c-4529-922d-0ee284c2ccc2	2bac9feb-8e54-44cd-9393-0f84e9b236be	uploads/users/2bac9feb-8e54-44cd-9393-0f84e9b236be/gallery/1782382718904_9d66da0a30a9f66d.jpg	21438	image/jpeg	f	1	2026-06-25 15:48:38.936+05:30	2026-06-25 15:48:38.936+05:30
8642189f-0450-4320-8883-9ab9a2f8d52a	2bac9feb-8e54-44cd-9393-0f84e9b236be	uploads/users/2bac9feb-8e54-44cd-9393-0f84e9b236be/gallery/1782382735212_0747a1b9e81255e4.jpg	49656	image/jpeg	t	0	2026-06-25 15:48:55.27+05:30	2026-06-25 15:48:55.27+05:30
3984c2c4-54cc-4e73-a2be-2809bcefeb26	2bac9feb-8e54-44cd-9393-0f84e9b236be	uploads/users/2bac9feb-8e54-44cd-9393-0f84e9b236be/gallery/1782382735274_d03b3c51b83b29ca.jpg	21438	image/jpeg	f	1	2026-06-25 15:48:55.304+05:30	2026-06-25 15:48:55.305+05:30
c37dbd70-c30f-47d8-8561-d61549bb3de8	444f8f5f-9c18-43fd-956a-b0e41a79292b	uploads/users/444f8f5f-9c18-43fd-956a-b0e41a79292b/gallery/1782455746583_21de96d9cf75e48b.jpg	15105	image/jpeg	t	0	2026-06-26 12:05:46.607+05:30	2026-06-26 12:05:46.607+05:30
1f6d078c-5348-493b-ab01-d6f7d63eddae	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	uploads/users/7bcb98f3-632e-44e8-8cfc-ec9a2f63011e/gallery/1782477659619_d6510f57886f3145.jpg	190124	image/jpeg	t	0	2026-06-26 18:10:59.967+05:30	2026-06-26 18:10:59.967+05:30
461e2dd3-5ac8-404d-859c-70edd1e1c940	55d60813-00a5-4059-821f-8bf6da1d6262	uploads/users/55d60813-00a5-4059-821f-8bf6da1d6262/gallery/1782719232866_00f07341906f1b82.jpg	12276	image/jpeg	t	0	2026-06-29 13:17:12.92+05:30	2026-06-29 13:17:12.921+05:30
4ff4c491-44c5-4a0a-a1a0-d868e7dc97fd	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	uploads/users/b363828d-17ea-4f00-8a8a-9ecb6ba8f856/gallery/1782818299465_1a5abc3a98fb46f9.jpg	27392	image/jpeg	t	0	2026-06-30 16:48:19.526+05:30	2026-06-30 16:48:19.526+05:30
ed0a0347-7ed7-4c36-910d-206f350d85e9	326982fd-3909-4791-b8d4-66efbfaf2734	uploads/users/326982fd-3909-4791-b8d4-66efbfaf2734/gallery/1782984641475_6f18da7db8267853.jpg	26211	image/jpeg	t	0	2026-07-02 15:00:41.589+05:30	2026-07-02 15:00:41.59+05:30
fbe9f2ec-7c44-45cb-ab02-83e8a4579f5f	71da26fc-a3a3-434a-aa6f-73220fd29fdd	uploads/users/71da26fc-a3a3-434a-aa6f-73220fd29fdd/gallery/1783342438465_fb60fd90b6d1c155.jpg	11019	image/jpeg	t	0	2026-07-06 18:23:58.519+05:30	2026-07-06 18:23:58.52+05:30
db06021f-61ab-46cc-9972-b5e58bb117e4	71da26fc-a3a3-434a-aa6f-73220fd29fdd	uploads/users/71da26fc-a3a3-434a-aa6f-73220fd29fdd/gallery/1783342447700_ef527808ee22f326.jpg	11019	image/jpeg	t	0	2026-07-06 18:24:07.72+05:30	2026-07-06 18:24:07.72+05:30
218ad76f-4ed2-4114-a93a-111e180c732a	095d1b94-1a8b-47c2-b912-c9031f0d9fcb	uploads/users/095d1b94-1a8b-47c2-b912-c9031f0d9fcb/gallery/1783345492326_32815a7e272ae1dc.jpg	3668	image/jpeg	t	0	2026-07-06 19:14:52.348+05:30	2026-07-06 19:14:52.352+05:30
d7f17591-418e-4d80-ab5b-3077babae477	095d1b94-1a8b-47c2-b912-c9031f0d9fcb	uploads/users/095d1b94-1a8b-47c2-b912-c9031f0d9fcb/gallery/1783345492371_0d2dfc6ba5aaa38d.jpg	3668	image/jpeg	f	1	2026-07-06 19:14:52.382+05:30	2026-07-06 19:14:52.383+05:30
a8c9fe39-975f-4b0c-87fe-0c13018eab63	6d861d92-f6c6-45f7-b444-7315a2685465	uploads/users/6d861d92-f6c6-45f7-b444-7315a2685465/gallery/1783345934749_d98c54260c80f57f.jpg	11019	image/jpeg	t	0	2026-07-06 19:22:14.769+05:30	2026-07-06 19:22:14.769+05:30
179eab45-b18f-4b38-8015-73f08a626ac5	6d861d92-f6c6-45f7-b444-7315a2685465	uploads/users/6d861d92-f6c6-45f7-b444-7315a2685465/gallery/1783345934780_9d7f3e47d17c7343.jpg	11019	image/jpeg	f	1	2026-07-06 19:22:14.799+05:30	2026-07-06 19:22:14.799+05:30
\.


--
-- Data for Name: user_preferences; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_preferences (id, user_id, preferred_venues, preferred_crowd_size, music_preference, drink_preference, smoking_preference, preferred_genders, min_age_preference, max_age_preference, min_budget, max_budget, budget_range, party_time_preference, group_size_preference, match_distance_km, show_me_in_matching, booking_alerts_enabled, created_at, updated_at) FROM stdin;
3cd841c0-b1c1-4264-a6a5-688ab64b6dce	ccb35417-49f8-474d-8d33-6f4e9d7738c0	{}	\N	{TECHNO,JAZZ}	{}	NON-SMOKER	{WOMEN,ALL}	21	35	\N	\N	premium	\N	\N	10	t	f	2026-06-16 15:35:40.55+05:30	2026-06-16 15:35:43.474+05:30
7178b4fe-2de6-455e-8df1-2297048747aa	681a88ab-5628-4081-af04-22aeb74daef2	{}	\N	{}	{}	\N	{}	18	60	\N	\N	\N	\N	\N	10	t	f	2026-06-16 15:59:26.19+05:30	2026-06-16 15:59:26.19+05:30
99d5125b-0283-48e8-b0c6-bf538c82650e	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	{}	\N	{TECHNO,HOUSE}	{}	NON-SMOKER	{ALL}	21	35	\N	\N	2000-10000	\N	\N	10	t	f	2026-06-16 15:59:36.405+05:30	2026-06-16 16:00:21.813+05:30
87821bc5-7633-4c93-8ff5-e0dce1d6dcad	55d60813-00a5-4059-821f-8bf6da1d6262	{}	\N	{}	{}	\N	{}	18	60	\N	\N	\N	\N	\N	10	t	f	2026-06-16 16:59:20.306+05:30	2026-06-16 16:59:20.306+05:30
363bf2c0-e3c6-4782-b9c2-9b921276395a	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	{}	\N	{TECHNO,HOUSE,RNB,BASS,DISCO,"DARK WAVE",AMAPIANO,"HIP HOP",JAZZ,EDM}	{}	NON-SMOKER	{WOMEN}	21	28	\N	\N	2000-50000	\N	\N	10	t	f	2026-06-16 18:32:21.676+05:30	2026-06-16 18:33:29.399+05:30
e80e90ad-d653-4d98-aba3-74ede5dbe722	1aa75230-368e-4dc9-aaec-378904c1377b	{}	\N	{BOLLYWOOD,PUNJABI,SUFI,"LIVE BANDS"}	{SOCIALLY}	SOCIALLY	{MEN}	21	35	\N	\N	2000-10000	\N	\N	10	t	f	2026-06-23 14:36:31.116+05:30	2026-06-23 14:38:29.09+05:30
ba5b8ff3-e55b-44a2-af41-2d7880bc17d2	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	{}	\N	{BOLLYWOOD,PUNJABI,"HIP HOP",INDIE}	{SOCIALLY}	NON-SMOKER	{ALL}	21	35	\N	\N	2000-10000	\N	\N	10	t	f	2026-06-23 14:49:06.188+05:30	2026-06-23 14:50:00.094+05:30
dba2d3fe-2591-4ce8-915a-10379c93316d	444f8f5f-9c18-43fd-956a-b0e41a79292b	{}	\N	{BOLLYWOOD,PUNJABI,KONKANI,EDM,JAZZ}	{SOCIALLY}	SOCIALLY	{ALL}	21	35	\N	\N	2000-10000	\N	\N	10	t	f	2026-06-23 15:40:11.499+05:30	2026-06-23 15:45:24.274+05:30
c7e6aafa-c730-4ada-8c59-1b338f40b57c	6b5bd1f2-3d3f-4533-bfd2-61de0b21e299	{}	\N	{}	{}	\N	{}	18	60	\N	\N	\N	\N	\N	10	t	f	2026-06-25 12:16:15.324+05:30	2026-06-25 12:16:15.324+05:30
3d60a6c0-77c3-4fbe-8936-f790b9532225	71da26fc-a3a3-434a-aa6f-73220fd29fdd	{}	\N	{BOLLYWOOD,PUNJABI,EDM,JAZZ}	{SOCIALLY}	NON-SMOKER	{WOMEN}	21	35	\N	\N	2000-10000	\N	\N	10	t	f	2026-07-06 18:19:39.477+05:30	2026-07-06 18:23:21.196+05:30
af11bec4-9c03-42f1-b3e9-15ff7e741f03	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	{}	\N	{}	{}	\N	{}	18	60	\N	\N	\N	\N	\N	10	t	f	2026-06-30 15:26:08.818+05:30	2026-06-30 15:26:08.818+05:30
01cceab6-743e-4720-bd5f-331aedd54dc0	dd2efb63-a121-4f55-ac86-8c43da14fcef	{}	\N	{}	{}	\N	{}	18	60	\N	\N	\N	\N	\N	10	t	f	2026-06-30 17:53:29.212+05:30	2026-06-30 17:53:29.212+05:30
94297ce8-0af3-4503-957d-e667a2210f88	6bdc7560-5b6c-4cb4-b72b-1666fddfa5f2	{}	\N	{}	{}	\N	{}	18	60	\N	\N	\N	\N	\N	10	t	f	2026-07-01 15:05:53.928+05:30	2026-07-01 15:05:53.928+05:30
9b08a6da-8339-4f73-beb4-fa7e3ddea048	64786496-e9b0-4ecb-8285-3095ef3bcf16	{}	\N	{}	{}	\N	{}	18	60	\N	\N	\N	\N	\N	10	t	f	2026-07-01 15:38:30.39+05:30	2026-07-01 15:38:30.39+05:30
0d71c06b-16d6-48b6-9035-53d20cda1222	326982fd-3909-4791-b8d4-66efbfaf2734	{}	\N	{}	{}	\N	{}	18	60	\N	\N	\N	\N	\N	10	t	f	2026-07-02 14:55:53.878+05:30	2026-07-02 14:55:53.878+05:30
cb00ed63-f626-40a1-bee7-48ee2c8169d9	400a3048-dba7-4d56-9d10-cb5d7c0f18a0	{}	\N	{}	{}	\N	{}	18	60	\N	\N	\N	\N	\N	10	t	f	2026-07-02 20:13:31.624+05:30	2026-07-02 20:13:31.624+05:30
6523ad98-6e73-4753-ac67-44f9eb0d9b79	37c1bb21-26d1-4082-a1da-871a16b0b232	{}	\N	{}	{}	\N	{}	18	60	\N	\N	\N	\N	\N	10	t	f	2026-07-02 20:23:18.604+05:30	2026-07-02 20:23:18.604+05:30
93919423-811a-43e3-8b59-faf6fa88056c	7198fd2d-abfc-4ebb-b819-00ce75f493d2	{}	\N	{}	{}	\N	{}	18	60	\N	\N	\N	\N	\N	10	t	f	2026-07-03 12:43:50.235+05:30	2026-07-03 12:43:50.235+05:30
ca10aef3-e8db-49b6-9724-46247e0917fd	dd2f25ca-d7e1-4670-a9c3-24478c9e8c3e	{}	\N	{BOLLYWOOD,PUNJABI}	{SOCIALLY}	NON-SMOKER	{ALL}	21	35	\N	\N	2000-10000	\N	\N	10	t	f	2026-07-03 13:21:37.191+05:30	2026-07-03 13:23:34.767+05:30
a3d000f3-e7b2-49f0-bf69-27b028f6d194	e4bcd759-8b6d-4900-abd8-f11ebbc830a4	{}	\N	{BOLLYWOOD,PUNJABI}	{SOCIALLY}	NON-SMOKER	{ALL}	21	35	\N	\N	2000-10000	\N	\N	10	t	f	2026-07-03 15:15:40.28+05:30	2026-07-03 15:16:58.199+05:30
89979c12-780d-4b05-8db1-55dafce2c0f9	2bac9feb-8e54-44cd-9393-0f84e9b236be	{}	\N	{BOLLYWOOD,PUNJABI,SUFI,"LIVE BANDS",KONKANI}	{NEVER}	NON-SMOKER	{ALL}	21	35	\N	\N	2000-15000	\N	\N	10	t	f	2026-06-25 15:42:49.805+05:30	2026-07-04 16:39:17.478+05:30
a6a533ab-47f0-4a98-acb0-3e07071602b0	b5bf9672-2e0f-4616-838e-5f8591862855	{}	\N	{BOLLYWOOD,PUNJABI}	{SOCIALLY}	REGULARLY	{ALL}	21	35	\N	\N	2000-10000	\N	\N	10	t	f	2026-07-06 16:45:28.826+05:30	2026-07-06 16:46:20.413+05:30
7386f37f-a722-43ac-ad97-97342381c63e	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	{}	\N	{}	{}	\N	{}	18	60	\N	\N	\N	\N	\N	10	t	f	2026-07-06 17:33:01.261+05:30	2026-07-06 17:33:01.261+05:30
02d9f3de-ce1e-40f9-9d35-a3fddcb2dc7f	095d1b94-1a8b-47c2-b912-c9031f0d9fcb	{}	\N	{BOLLYWOOD,PUNJABI,MARATHI,EDM}	{SOCIALLY}	NON-SMOKER	{ALL}	21	35	\N	\N	2000-10000	\N	\N	10	t	f	2026-07-06 18:56:56.642+05:30	2026-07-06 19:14:53.059+05:30
7efe3abe-0867-4482-aefc-21d559024888	6d861d92-f6c6-45f7-b444-7315a2685465	{}	\N	{BOLLYWOOD,PUNJABI,INDIE}	{SOCIALLY}	NON-SMOKER	{ALL}	21	35	\N	\N	2000-10000	\N	\N	10	t	f	2026-07-06 19:20:58.549+05:30	2026-07-06 19:22:14.917+05:30
\.


--
-- Data for Name: user_profiles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_profiles (id, user_id, display_name, bio, gender, city, occupation, company, education, relationship_status, looking_for, instagram_handle, spotify_profile, created_at, updated_at, nightlife_preference, interests, daily_match_requests_count, daily_likes_count, daily_posts_count, last_activity_date) FROM stdin;
62c1ee0d-3641-42b8-8496-1f6981c01e94	095d1b94-1a8b-47c2-b912-c9031f0d9fcb	Chintu Sharma	This is a test story.	MALE	Pune	Designer	\N	Pune	\N	{"NEW FRIENDS",NETWORKING,"EVENT COMPANIONS"}	\N	\N	2026-07-06 18:56:56.641+05:30	2026-07-06 19:14:53.056+05:30	{"ROOFTOP LOUNGE","FINE DINING","SPORTS SCREENING"}	{TRAVEL,PHOTOGRAPHY,STARTUPS,FASHION}	0	0	0	\N
e240cf4c-6a1f-4bf9-ad2a-0438eec7be35	681a88ab-5628-4081-af04-22aeb74daef2	Bandu Darokar	\N	MALE	Pune	\N	\N	\N	\N	{}	\N	\N	2026-06-16 15:59:26.189+05:30	2026-06-16 15:59:26.189+05:30	{}	{}	0	0	0	\N
8bb07f41-e010-4e2b-ba23-bdd3de156793	7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	Vishal Karpe		MALE	Pune		\N		\N	{PARTNER}	\N	\N	2026-06-16 15:59:36.405+05:30	2026-06-16 16:00:21.812+05:30	{}	{}	0	0	0	\N
bda072f6-7063-445d-8fa0-7ae5d00c4446	55d60813-00a5-4059-821f-8bf6da1d6262	Bandu Darokar	\N	MALE	Pune	\N	\N	\N	\N	{}	\N	\N	2026-06-16 16:59:20.305+05:30	2026-06-16 16:59:20.305+05:30	{}	{}	0	0	0	\N
a3e84533-fc97-4f95-af9d-f18d91d45f90	d124b298-6374-43bb-b7a4-2c3f1ba1bd84	Nikhil Nerkar	Weekend explorer who enjoys rooftop lounges, live music, DJ nights, and trying new places. I believe the best memories are created through shared experiences, good vibes, and meaningful conversations.	MALE	Pune	Business	\N	Pune	\N	{PARTNER}	\N	\N	2026-06-16 18:32:21.675+05:30	2026-06-16 18:33:29.398+05:30	{}	{}	0	0	0	\N
2a416484-c0ed-4b65-a2e9-4a07e9c47e23	1aa75230-368e-4dc9-aaec-378904c1377b	Rani Kollha	Tell the night about yourself.	FEMALE	Pune		\N		\N	{"NEW FRIENDS","SOCIAL OUTINGS","ACTIVITY PARTNER"}	\N	\N	2026-06-23 14:36:31.115+05:30	2026-06-23 14:38:29.089+05:30	{"ROOFTOP LOUNGE",PUBS,CLUBS}	{TRAVEL,FITNESS,MOVIES,MUSIC,FOOD}	0	0	0	\N
e3afa011-0c30-4cc1-93dc-8c34bd3a87b8	c45a3c3d-1032-417d-841d-fe5af2dcb0f7	Pinki Wale	This is a test story.	FEMALE	Pune		\N		\N	{"NEW FRIENDS",NETWORKING,"EVENT COMPANIONS"}	\N	\N	2026-06-23 14:49:06.187+05:30	2026-06-23 14:50:00.093+05:30	{"ROOFTOP LOUNGE",PUBS,CLUBS,"DJ NIGHTS"}	{TRAVEL,PHOTOGRAPHY,GAMING,SPORTS,NATURE}	0	0	0	\N
aa607d81-cdb2-4794-bcf1-e71686a80bff	444f8f5f-9c18-43fd-956a-b0e41a79292b	kalpesh shinde	test	MALE	Pune		\N		\N	{"SOCIAL OUTINGS",NETWORKING,"ACTIVITY PARTNER","EVENT COMPANIONS"}	\N	\N	2026-06-23 15:40:11.498+05:30	2026-06-23 15:45:24.273+05:30	{"ROOFTOP LOUNGE","LIVE MUSIC","DJ NIGHTS","SPORTS SCREENING"}	{FITNESS,FOOD,BUSINESS,ENTREPRENEURSHIP,DANCING}	0	0	0	\N
91ef2c7e-f517-4771-be0c-5311c08cc5ad	6b5bd1f2-3d3f-4533-bfd2-61de0b21e299	umesh wagh	\N	MALE	Pune	\N	\N	\N	\N	{}	\N	\N	2026-06-25 12:16:15.323+05:30	2026-06-25 12:16:15.323+05:30	{}	{}	0	0	0	\N
00ca87e9-fcfe-4fda-8038-d202bfd24252	2bac9feb-8e54-44cd-9393-0f84e9b236be	Aditya Kate	This is a story of Aditya Kate.	MALE	Pune		\N		\N	{"NEW FRIENDS",NETWORKING}	\N	\N	2026-06-25 15:42:49.804+05:30	2026-06-25 15:45:57.416+05:30	{"ROOFTOP LOUNGE","FINE DINING","LIVE MUSIC"}	{TRAVEL,FITNESS,MOVIES,MUSIC,BUSINESS,SPORTS,GAMING,DANCING,FOOD,PETS,NATURE,FASHION,ART,ADVENTURE,ENTREPRENEURSHIP,PHOTOGRAPHY,STARTUPS,READING}	0	0	0	\N
4bbea15d-82f9-4b77-8d70-ebcef92396d1	b363828d-17ea-4f00-8a8a-9ecb6ba8f856	Siya Goyal	\N	FEMALE	Pune	\N	\N	\N	\N	{}	\N	\N	2026-06-30 15:26:08.818+05:30	2026-06-30 15:26:08.818+05:30	{}	{}	0	0	0	\N
17a94148-531c-4b40-8560-7a2d75db8e1c	dd2efb63-a121-4f55-ac86-8c43da14fcef	Umesh Dahare	\N	MALE	Pune	\N	\N	\N	\N	{}	\N	\N	2026-06-30 17:53:29.211+05:30	2026-06-30 17:53:29.211+05:30	{}	{}	0	0	0	\N
b4499d43-18a4-48bd-a293-2447625fa9a9	6bdc7560-5b6c-4cb4-b72b-1666fddfa5f2	ssj shf	\N	MALE	Pune	\N	\N	\N	\N	{}	\N	\N	2026-07-01 15:05:53.928+05:30	2026-07-01 15:05:53.928+05:30	{}	{}	0	0	0	\N
c362f7ac-dd8c-4fc6-a578-90f3085849cc	64786496-e9b0-4ecb-8285-3095ef3bcf16	Bandu Darokar	\N	MALE	Pune	\N	\N	\N	\N	{}	\N	\N	2026-07-01 15:38:30.389+05:30	2026-07-01 15:38:30.389+05:30	{}	{}	0	0	0	\N
19d7958c-41b3-4e3d-80ee-5231b8af01ed	326982fd-3909-4791-b8d4-66efbfaf2734	Amol Bodade	\N	MALE	Pune	\N	\N	\N	\N	{}	\N	\N	2026-07-02 14:55:53.878+05:30	2026-07-02 14:55:53.878+05:30	{}	{}	0	0	0	\N
c395092a-3835-423a-9020-88e05134100b	400a3048-dba7-4d56-9d10-cb5d7c0f18a0	Jalindra Shinde	\N	MALE	Pune	\N	\N	\N	\N	{}	\N	\N	2026-07-02 20:13:31.624+05:30	2026-07-02 20:13:31.624+05:30	{}	{}	0	0	0	\N
8461c602-ecc4-4aa2-bc07-cfba5354bfb3	37c1bb21-26d1-4082-a1da-871a16b0b232	Jalindra Shinde	\N	MALE	Pune	\N	\N	\N	\N	{}	\N	\N	2026-07-02 20:23:18.604+05:30	2026-07-02 20:23:18.604+05:30	{}	{}	0	0	0	\N
0897ebcf-9fd8-4bfc-a9ed-8974af4aca67	7198fd2d-abfc-4ebb-b819-00ce75f493d2	om shinde	\N	MALE	Pune	\N	\N	\N	\N	{}	\N	\N	2026-07-03 12:43:50.234+05:30	2026-07-03 12:43:50.234+05:30	{}	{}	0	0	0	\N
398097f5-b07d-4e99-9bdc-b96ff8a8541f	dd2f25ca-d7e1-4670-a9c3-24478c9e8c3e	raj shinde	test	MALE	Pune		\N		\N	{"NEW FRIENDS","SOCIAL OUTINGS"}	\N	\N	2026-07-03 13:21:37.191+05:30	2026-07-03 13:23:34.765+05:30	{"ROOFTOP LOUNGE",PUBS,"DJ NIGHTS"}	{FOOD,GAMING,PHOTOGRAPHY}	0	0	0	\N
1d9881d8-0695-4564-9d5a-5db1bfa076f7	e4bcd759-8b6d-4900-abd8-f11ebbc830a4	Abcd Ab	test	MALE	Pune		\N		\N	{"NEW FRIENDS","EVENT COMPANIONS","MEANINGFUL CONNECTIONS"}	\N	\N	2026-07-03 15:15:40.279+05:30	2026-07-03 15:16:58.197+05:30	{"ROOFTOP LOUNGE","LIVE MUSIC","DJ NIGHTS"}	{TRAVEL,PHOTOGRAPHY,SPORTS,READING,PETS,FASHION}	0	0	0	\N
6d7d5202-6c0c-48a7-bbac-83781977ab47	ccb35417-49f8-474d-8d33-6f4e9d7738c0	Test User	Looking for a fun night out.	MALE	Pune	\N	\N	\N	\N	{}	\N	\N	2026-06-16 15:35:40.468+05:30	2026-06-16 15:35:43.446+05:30	{}	{}	0	0	0	\N
960e4294-1c95-486d-a040-b2a54a613f6e	b5bf9672-2e0f-4616-838e-5f8591862855	danny sing		MALE	Pune		\N		\N	{}	\N	\N	2026-07-06 16:45:28.824+05:30	2026-07-06 16:46:20.411+05:30	{}	{}	0	0	0	\N
da3d2875-e0db-4e9c-801e-65ebb201c801	3781b0f8-7d2f-4bea-a289-7ad9d934bec1	kiara goyal	\N	FEMALE	Pune	\N	\N	\N	\N	{}	\N	\N	2026-07-06 17:33:01.26+05:30	2026-07-06 17:33:01.26+05:30	{}	{}	0	0	0	\N
7a616339-f3ec-414f-bbc3-93467bf52004	71da26fc-a3a3-434a-aa6f-73220fd29fdd	Amir Khan	This is a test history.	MALE	Pune	Developer	\N	Pune	\N	{"NEW FRIENDS","ACTIVITY PARTNER","MEANINGFUL CONNECTIONS"}	\N	\N	2026-07-06 18:19:39.477+05:30	2026-07-06 18:23:21.195+05:30	{"ROOFTOP LOUNGE","FINE DINING","SPORTS SCREENING"}	{TRAVEL,PHOTOGRAPHY,STARTUPS,FASHION}	0	0	0	\N
fadd45d3-cea8-4794-bd30-21ea6749892b	6d861d92-f6c6-45f7-b444-7315a2685465	Jaju Khade	Test story	MALE	Pune	Teacher	\N		\N	{"SOCIAL OUTINGS","EVENT COMPANIONS","MEANINGFUL CONNECTIONS"}	\N	\N	2026-07-06 19:20:58.548+05:30	2026-07-06 19:22:14.916+05:30	{"ROOFTOP LOUNGE","FINE DINING"}	{FITNESS,PHOTOGRAPHY,PETS}	0	0	0	\N
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.users (id, email, phone, password_hash, first_name, last_name, date_of_birth, role, is_verified, is_active, mfa_enabled, mfa_secret, profile_image_url, last_login_at, is_online, last_active_at, no_show_count, created_at, updated_at, fcm_token, cleared_notifications_at, block_count, is_autoblocked, autoblocked_reason) FROM stdin;
444f8f5f-9c18-43fd-956a-b0e41a79292b	kalpesh@micraft.co.in	8975829218	$2a$12$NHtUHvL226OdJPp1g/q4U.XMa9LtkDcREHjJ2HxC9MDkz5n14oi/O	kalpesh	shinde	2001-11-24	customer	f	t	f	\N	\N	2026-06-26 13:33:35.521+05:30	f	2026-06-26 13:34:46.113+05:30	0	2026-06-23 15:40:11.489+05:30	2026-07-07 18:10:26.416+05:30	ddqg51hAT8uNePOtQWkjKs:APA91bE9EMJOK1Vb1Ngc2EkAqZzTGHnq14WvAPQYfFGomzMqshPlta0up9aYp-aWxuXRPUBs_LYYObZ4a1vK6NRsDZtcY5xqk7ROdHrzUXKAa5qbEFpKGS8	\N	0	f	\N
400a3048-dba7-4d56-9d10-cb5d7c0f18a0	shinde@micraft.co.in	9404042720	$2a$12$2XmUcg1mQVuWASlbNGF2yOsvuXWcFl4IMR0hktM7UAZAemNHBDiQC	Jalindra	Shinde	1976-04-09	customer	f	t	f	\N	\N	\N	t	2026-07-02 20:18:33.487+05:30	0	2026-07-02 20:13:31.61+05:30	2026-07-02 20:18:33.487+05:30	dPrTuWCmQlWeZ95PfjtHnm:APA91bF2I3kbjfP-hsXNII67CFlp3wpA03BGtEvy-08mRiTCFfbmvQqdLIIylmFJkXfiPh6eO_zZfv07ivIThmYYTBwbCAki3oJg9cB7Cw3lF7HF3s8c5N0	\N	0	f	\N
326982fd-3909-4791-b8d4-66efbfaf2734	amol@gmail.com	9999899999	$2a$12$cN3lvm0Dk0hwtVK7lTlWuuAB.sCeB9m90hBWIP0jmVumL3dTdgFw6	Amol	Bodade	2003-07-06	customer	f	t	f	\N	\N	2026-07-02 15:16:24.484+05:30	f	2026-07-02 16:29:10.166+05:30	0	2026-07-02 14:55:53.86+05:30	2026-07-02 16:29:10.166+05:30	\N	\N	0	f	\N
ccb35417-49f8-474d-8d33-6f4e9d7738c0	testuser@example.com	9876543210	$2a$10$8wt3lC2i8cfs2kPj93Sn2.mZLhnqTvqieApVnZ8sYQoLiGrnGd4n2	Updated	User	1995-01-01	customer	t	t	f	NNIC4I2UFBKG43CYGEZXSQLOEQSHOMZPOFWG6SJMMM4FEYRGINHA	\N	2026-06-16 15:35:43.382+05:30	f	\N	0	2026-06-16 15:35:40.289+05:30	2026-06-16 15:35:43.382+05:30	\N	\N	0	f	\N
2bac9feb-8e54-44cd-9393-0f84e9b236be	aditya@gmail.com	8978675645	$2a$12$n1J5zUZPOlo5oaV1r6fth.sQjjcQDSavZgirsB3hWyk4e27AP.A32	Aditya	Kate	2003-02-11	customer	f	t	f	\N	\N	2026-07-07 18:36:18.781+05:30	f	2026-07-07 18:42:24.535+05:30	0	2026-06-25 15:42:49.795+05:30	2026-07-07 18:42:24.535+05:30	cDwzTLfKRsSq9zt-6RdILo:APA91bHRsFbFbpjNk65EObh7ufR8x5U3TbQmFpP6BjwCIqKPe2rORrdxdiQLgOQhcreqRZyACo7TOJWN-kBTT2K8Asw9Hmy9vD_4IXAE-UkY1KvJfPs15vY	2026-07-07 18:38:12.182+05:30	0	f	\N
6b5bd1f2-3d3f-4533-bfd2-61de0b21e299	umesh@gmail.com	9067565606	$2a$12$j6MPuJZLtAM6tfY.fV3LI.oIu56.aXa.JTnSrc/aFAUplRAxHX6LG	umesh	wagh	2002-06-30	customer	f	t	f	\N	\N	\N	t	2026-06-25 12:21:47.373+05:30	0	2026-06-25 12:16:15.303+05:30	2026-06-25 12:21:47.373+05:30	cEM4J6vySouIEfWhDMUVub:APA91bHr1yMPFF6S6-oeFNe7KV4gbq1TwzaN2gOYQI8aXpny0hGamGQ_vscv_hDEZi_vkBz6xao0RTkixP5dhXpE98XRWsB94qDqqeEuet3eJ7pUjb2odG0	\N	0	f	\N
d124b298-6374-43bb-b7a4-2c3f1ba1bd84	nikhil.n@ssklworld.com	9421004137	$2a$12$Ncgccw7BIYjhsUrBbsYqAuT9bzuS7JbLKExT/bTesFsSyN5RqhBDu	Nikhil	Nerkar	2002-12-04	customer	t	t	f	\N	\N	2026-07-07 14:36:47.415+05:30	f	2026-07-08 17:33:12.824+05:30	0	2026-06-16 18:32:21.66+05:30	2026-07-08 17:33:12.824+05:30	eFVy9tQgQgykfeKhitdasT:APA91bEVmtND58fdv5NzxLE_Qx7uxxsVD86V0AjyKQ-mJBoRKRnB-7hz8FyJjFJeaq44-0ctuTSUTHACg8A0sDFQoykJ58IRktj1Q_iGwuysyy9Qtb3V2GA	2026-07-08 11:37:37.724+05:30	0	f	\N
6bdc7560-5b6c-4cb4-b72b-1666fddfa5f2	fhdkv@gmail.com	9999999999	$2a$12$xk2qcmyKYYTfjfEwAOJ4CuiFVNpluJvdeeUcGk69qd47.UimiR5.W	ssj	shf	2002-07-05	customer	f	t	f	\N	\N	\N	t	2026-07-01 15:30:31.238+05:30	0	2026-07-01 15:05:53.914+05:30	2026-07-01 15:30:31.239+05:30	clrog3kjSESyVsxO2S1XqP:APA91bEgtFRFSmT31F5Pm1dkK3JC02XMU8nBqsR7HLkSnjSMSCeW428yqt1xFtZceSPWPtAlB7x2kG-EKlK0U5RhN1P3QsJ9W0CwuY9wKdItMhCxuGpCSXU	\N	0	f	\N
71da26fc-a3a3-434a-aa6f-73220fd29fdd	amir@gmail.com	9988776655	$2a$12$kr28JoAR14Hkm2R8ol3s4.5a4F43OC5vlZWdxRSLJouEG.ymQEtQC	Amir	Khan	2002-07-10	customer	f	t	f	\N	\N	2026-07-06 18:24:06.919+05:30	f	2026-07-06 18:31:29.162+05:30	0	2026-07-06 18:19:39.463+05:30	2026-07-06 18:31:29.163+05:30	\N	\N	0	f	\N
7bcb98f3-632e-44e8-8cfc-ec9a2f63011e	vishal.karpe@micraft.co.in	7028451855	$2a$12$QgcFd6d4YwZhyF8VQ51IWO/y7RZH7.XEZW15vvv/OpwtFfWSzFyOy	Vishal	Karpe	2000-07-24	customer	f	t	f	\N	\N	2026-07-07 19:26:15.605+05:30	f	2026-07-07 19:29:21.351+05:30	0	2026-06-16 15:59:36.392+05:30	2026-07-07 19:29:21.352+05:30	c6F8PZdQTrCE2D4ENeYm01:APA91bFD3kiFMiq6081VFKJ0KDgXeSmwjSNkDEHvu6dyMcTjCKDvw08h6M6MLG2_vHz_lVwtSOnsLbxu9dWkTV9Bu3tX2O_KsaXZerRP7Tzmk70uipqKEPA	2026-07-07 19:26:24.603+05:30	0	f	\N
b363828d-17ea-4f00-8a8a-9ecb6ba8f856	goyal@gmail.com	9699320615	$2a$12$zmGzD8E3Rc82akQQ/xS1b.rm/D/rdHXagvL3rSrPu8LEhwoBcU3/a	Siya	Goyal	2002-07-04	customer	f	t	f	\N	\N	2026-06-30 16:48:18.624+05:30	f	2026-07-01 11:01:14.326+05:30	0	2026-06-30 15:26:08.808+05:30	2026-07-01 11:01:14.327+05:30	dlDfkL8CTtqdTKIZtDRima:APA91bG04r22na9HtgKAbdqWA2ot0YduajYYpQYB8jz3GgK4Kk_aqdjm7s1PzCGj7lWukhBkDzvhxQHP4rnYIUdXhKIRfSZH1SVs4lFLnBf4fqEB7_c7qAY	\N	0	f	\N
37c1bb21-26d1-4082-a1da-871a16b0b232	shinde@micraft.com	9404042721	$2a$12$uvTDwSGSyXlSKhxRAdA2ees2yk2o6mfYYurI1/a4Zbrz.jGPln2v2	Jalindra	Shinde	1985-07-23	customer	f	t	f	\N	\N	\N	f	2026-07-02 20:30:04.923+05:30	0	2026-07-02 20:23:18.593+05:30	2026-07-02 20:30:04.924+05:30	dPrTuWCmQlWeZ95PfjtHnm:APA91bF2I3kbjfP-hsXNII67CFlp3wpA03BGtEvy-08mRiTCFfbmvQqdLIIylmFJkXfiPh6eO_zZfv07ivIThmYYTBwbCAki3oJg9cB7Cw3lF7HF3s8c5N0	\N	0	f	\N
64786496-e9b0-4ecb-8285-3095ef3bcf16	saurabh@gmail.com	8282828282	$2a$12$iZ0gcqsD0BngAGuroMvZuu8T/qdEjAW4daxsMHG4rtXDXPnw40lfe	Saurabh	Burde	1982-07-05	customer	f	t	f	\N	\N	2026-07-02 12:24:52.742+05:30	t	2026-07-02 12:39:43.519+05:30	0	2026-07-01 15:38:30.379+05:30	2026-07-02 12:39:43.52+05:30	\N	\N	0	f	\N
dd2efb63-a121-4f55-ac86-8c43da14fcef	umesh@micraft.co.in	8723456732	$2a$12$QM1Asdwzb0rZi21qiEQS1e56c6iKC52iwROGRyoswW8N.oU93bHu6	Umesh	Dahare	2001-01-01	customer	f	t	f	\N	\N	2026-07-02 12:09:14.481+05:30	f	2026-07-02 12:09:26.73+05:30	0	2026-06-30 17:53:29.192+05:30	2026-07-02 12:09:26.73+05:30	\N	\N	0	f	\N
dd2f25ca-d7e1-4670-a9c3-24478c9e8c3e	raj@gmail.com	8796431258	$2a$12$T0VEqV0cdfsJad7BVfzgy.17jioQQQcI3Gx1t08ZqHJ2skV6wJ0ty	raj	shinde	2002-07-07	customer	f	t	f	\N	\N	\N	f	2026-07-03 15:04:04.732+05:30	0	2026-07-03 13:21:37.178+05:30	2026-07-03 15:04:04.733+05:30	eRsfy4MJQfeu_4hMlOhB9M:APA91bH3leOkHyZW00zpiI7sFdnGz9B9srZqeRRQiN_Y9s78mde8tkwsi_IjpKrUDwXx_4XafKTKwIrNuBXZIdrns0j4vEs06qxQ0aX6aLvUXt3twnaEThk	\N	0	f	\N
7198fd2d-abfc-4ebb-b819-00ce75f493d2	om@gmail.com	8909876787	$2a$12$8a9NC.YU93g0knG7Q64Dw.y0js9CRVvvVe6lObCsaeHVNqDBUl8vq	om	shinde	2002-07-07	customer	f	t	f	\N	\N	\N	f	2026-07-03 12:44:51.5+05:30	0	2026-07-03 12:43:50.209+05:30	2026-07-03 12:44:51.5+05:30	\N	\N	0	f	\N
b5bf9672-2e0f-4616-838e-5f8591862855	danny@gmail.com	7020574540	$2a$12$1MHAZrFD5oAWOudWvsv3puafINCOiEPiCvPW0ihIqDQ.phVNRNz.i	danny	sing	2002-07-10	customer	f	t	f	\N	\N	\N	t	2026-07-06 16:52:17.975+05:30	0	2026-07-06 16:45:28.797+05:30	2026-07-06 16:52:17.975+05:30	f0AttBHjT6CX4edosdRqcP:APA91bH0HQ1PATiiOOUwXVQfJHG_dvapHTFUP8rflw92LXepHDS-b8eIq0rBu9teewsX5yluMrTFl2VB2Sdupm2-wnPzG0sV0VYBUR6uQPkqhhq3m5-c_dM	\N	0	f	\N
6d861d92-f6c6-45f7-b444-7315a2685465	jaju@gmail.com	7657657657	$2a$12$kQFl3B14jyaL3fVTzxzLae6waDW3eVejIUlhnSLWD4RViaHn5VBFO	Jaju	Khade	2002-07-10	customer	f	t	f	\N	\N	2026-07-08 17:47:12.254+05:30	f	2026-07-08 18:02:51.615+05:30	0	2026-07-06 19:20:58.526+05:30	2026-07-08 18:02:51.615+05:30	\N	\N	0	f	\N
e4bcd759-8b6d-4900-abd8-f11ebbc830a4	abcd@micraft.co.in	8263946611	$2a$12$D97nnZNr2lWrk/egOiEwv.TQCHKZBEIHifAvSSkoRqmymVtJzzMji	Abcd	Ab	2002-07-07	customer	f	t	f	\N	\N	\N	f	2026-07-03 15:20:44.952+05:30	0	2026-07-03 15:15:40.27+05:30	2026-07-03 15:20:44.953+05:30	\N	\N	0	f	\N
681a88ab-5628-4081-af04-22aeb74daef2	admin@lunara.com	8263946636	$2a$10$RuJ9OqYvhTAP2hW896YrEOriwuXV.xhmCvPAiZrb90f8uRkYFqDsW	admin	admin	1977-06-16	admin	f	t	f	\N	\N	2026-07-07 18:27:48.164+05:30	t	2026-06-16 17:00:55.627+05:30	0	2026-06-16 15:59:26.169+05:30	2026-07-07 18:27:48.164+05:30	\N	\N	0	f	\N
3781b0f8-7d2f-4bea-a289-7ad9d934bec1	umeshwagh7979@gmail.com	9056361239	$2a$12$FYwohW8l/OGHWeODaeTj4OpYo0WYGx.CMLW54nS52itXeBRtyMjEK	kiara	goyal	1992-05-04	customer	f	t	f	\N	\N	\N	f	2026-07-08 17:54:30.113+05:30	0	2026-07-06 17:33:01.245+05:30	2026-07-08 17:54:30.114+05:30	cMOlHw0HTcO1u0OdQpPXDC:APA91bGTpudIU25U8w51rnUM8Na-QRHQ0dcH62qXl4e9qGM_rEb9DdoT32BZYm4iM29lMONbG-qprUvuyTirbh_CK-az_2n0cr5J9lhSd-IONa3fZer0PqQ	\N	0	f	\N
c45a3c3d-1032-417d-841d-fe5af2dcb0f7	pinki@gmail.com	9876543213	$2a$12$0c7XhRGzTEUzYs2KAj4RdujVROwYof6xyGAKVGR6ilqqHooCHnE2K	Pinki	Wale	2003-06-27	customer	f	t	f	\N	\N	2026-07-06 18:16:00.756+05:30	t	2026-07-06 18:19:40.77+05:30	0	2026-06-23 14:49:06.17+05:30	2026-07-06 18:19:40.77+05:30	clrog3kjSESyVsxO2S1XqP:APA91bEgtFRFSmT31F5Pm1dkK3JC02XMU8nBqsR7HLkSnjSMSCeW428yqt1xFtZceSPWPtAlB7x2kG-EKlK0U5RhN1P3QsJ9W0CwuY9wKdItMhCxuGpCSXU	\N	0	f	\N
1aa75230-368e-4dc9-aaec-378904c1377b	rani@gmail.com	9876543212	$2a$12$uh1G8zO/OsXazPtazKdOOOA5QqNNFtZC2uHRASE7rNxvSOp7mXPwG	Rani	Kollha	2000-06-27	customer	f	t	f	\N	\N	2026-07-09 12:00:15.012+05:30	f	2026-07-09 12:28:18.404+05:30	0	2026-06-23 14:36:31.096+05:30	2026-07-09 12:28:18.404+05:30	dPrTuWCmQlWeZ95PfjtHnm:APA91bF2I3kbjfP-hsXNII67CFlp3wpA03BGtEvy-08mRiTCFfbmvQqdLIIylmFJkXfiPh6eO_zZfv07ivIThmYYTBwbCAki3oJg9cB7Cw3lF7HF3s8c5N0	\N	1	f	\N
095d1b94-1a8b-47c2-b912-c9031f0d9fcb	chintu@gmail.com	8787878789	$2a$12$taUpgwHYjGJJMl/6tBwYN.HoAjJON9LGYsc.PxFa6VfjHkPRBn6Ay	Chintu	Sharma	2002-07-10	customer	f	t	f	\N	\N	\N	t	2026-07-06 19:20:59.445+05:30	0	2026-07-06 18:56:56.631+05:30	2026-07-06 19:20:59.445+05:30	\N	\N	0	f	\N
55d60813-00a5-4059-821f-8bf6da1d6262	bandu@micraft.co.in	8263946637	$2a$12$GMDwgx8GD3/Y1w7fNAPz7O1ja5s5Dh.ORLIlGsSjWXGPg2IAMmIbK	Bandu	Darokar	1977-06-16	customer	t	t	f	\N	\N	2026-07-09 13:40:24.893+05:30	t	2026-07-09 13:40:26.328+05:30	0	2026-06-16 16:59:20.055+05:30	2026-07-09 13:40:26.328+05:30	eRsfy4MJQfeu_4hMlOhB9M:APA91bH3leOkHyZW00zpiI7sFdnGz9B9srZqeRRQiN_Y9s78mde8tkwsi_IjpKrUDwXx_4XafKTKwIrNuBXZIdrns0j4vEs06qxQ0aX6aLvUXt3twnaEThk	2026-07-08 14:08:16.499+05:30	0	f	\N
\.


--
-- Data for Name: venue_compliance_logs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.venue_compliance_logs (id, venue_id, event_type, actor_email, ip_address, metadata, created_at) FROM stdin;
794caaa8-231b-415e-8d88-024ba151e06a	17887092-ea6a-4102-82a0-06aefdb1d79d	terms_accepted	admin@lunara.com	::ffff:103.29.157.218	{"userId": "681a88ab-5628-4081-af04-22aeb74daef2", "venueName": "LOVA", "termsAcceptedAt": "2026-06-16T11:23:28.521Z"}	2026-06-16 16:53:28.527+05:30
d07de8fe-9f26-4fc4-b394-ad836d50090c	17887092-ea6a-4102-82a0-06aefdb1d79d	confirmation_email_sent	admin@lunara.com	::ffff:103.29.157.218	{"expiresAt": "2026-06-19T11:23:28.520Z", "confirmUrl": "http://103.224.247.35:9076/api/venues/confirm/6b93c6505e2895799c7cf96267970f6717d284ae83f0066295c8f31893a7a156", "recipientName": "Bandu Darokar", "recipientEmail": "admin@lunara.com"}	2026-06-16 16:53:30.943+05:30
7cb97900-75f8-48da-946c-bc570e63a15c	17887092-ea6a-4102-82a0-06aefdb1d79d	status_changed	admin@lunara.com	::ffff:103.29.157.218	{"reason": "Admin updated status to approved", "newStatus": "approved", "oldStatus": "pending_confirmation"}	2026-06-16 16:55:31.129+05:30
dae661c7-9a8b-4483-ab20-6255b5d0867d	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	venue_live	admin@lunara.com	::ffff:103.29.157.218	{"liveAt": "2026-06-16T11:49:01.657Z", "reason": "Admin set status to Approved on creation — venue made Live directly", "venueName": "TETTORICCA"}	2026-06-16 17:19:01.664+05:30
dc6325ec-430a-4564-bffe-434c97c00765	a34456dc-fc25-4092-aae8-d3f8fd29d76f	terms_accepted	admin@lunara.com	::ffff:165.99.175.241	{"userId": "681a88ab-5628-4081-af04-22aeb74daef2", "venueName": "Favela | ONYX", "termsAcceptedAt": "2026-06-27T11:03:11.609Z"}	2026-06-27 16:33:11.618+05:30
9ef64356-54ae-4ec5-b037-7a5ede6afbf2	b50d85dd-ef32-4753-9e53-159ac11d8046	terms_accepted	admin@lunara.com	::ffff:165.99.175.241	{"userId": "681a88ab-5628-4081-af04-22aeb74daef2", "venueName": "Cafe Vanabella", "termsAcceptedAt": "2026-06-27T12:21:44.407Z"}	2026-06-27 17:51:44.415+05:30
278ec85f-caac-42ab-b925-503124579fb0	4311111f-8e89-4016-a39c-faf3d12eacf9	terms_accepted	admin@lunara.com	::ffff:165.99.175.178	{"userId": "681a88ab-5628-4081-af04-22aeb74daef2", "venueName": "Echho", "termsAcceptedAt": "2026-06-28T05:16:44.893Z"}	2026-06-28 10:46:44.9+05:30
d5bf6e72-0bc0-4347-89c7-5d32c81ec895	4311111f-8e89-4016-a39c-faf3d12eacf9	status_changed	admin@lunara.com	::ffff:103.164.240.116	{"reason": "Admin updated status to live", "newStatus": "live", "oldStatus": "pending_confirmation"}	2026-06-29 11:03:45.35+05:30
cef17827-e4dd-4cfb-87dd-b2a6ddba598e	b50d85dd-ef32-4753-9e53-159ac11d8046	status_changed	admin@lunara.com	::ffff:103.164.240.116	{"reason": "Admin updated status to live", "newStatus": "live", "oldStatus": "pending_confirmation"}	2026-06-29 11:03:58.901+05:30
a8ba7d67-001e-4508-b311-7459a1145d50	a34456dc-fc25-4092-aae8-d3f8fd29d76f	status_changed	admin@lunara.com	::ffff:103.164.240.116	{"reason": "Admin updated status to live", "newStatus": "live", "oldStatus": "pending_confirmation"}	2026-06-29 11:04:09.253+05:30
92838424-1209-43ef-92a4-60dfdd5e2699	ab320228-2d2f-41da-9d07-c9f5a915211e	terms_accepted	admin@lunara.com	::ffff:152.58.16.55	{"userId": "681a88ab-5628-4081-af04-22aeb74daef2", "venueName": "Sash", "termsAcceptedAt": "2026-07-02T18:43:15.027Z"}	2026-07-03 00:13:15.034+05:30
0e952864-b8b4-41de-ac57-24400d9e06c6	ab320228-2d2f-41da-9d07-c9f5a915211e	status_changed	admin@lunara.com	::ffff:152.58.16.55	{"reason": "Admin updated status to live", "newStatus": "live", "oldStatus": "pending_confirmation"}	2026-07-03 00:40:53.578+05:30
83d5827d-a021-480b-a797-b3eb211a179b	14292123-33fc-4c0f-b583-c2e532fd6c2d	terms_accepted	admin@lunara.com	::ffff:165.99.175.242	{"userId": "681a88ab-5628-4081-af04-22aeb74daef2", "venueName": "AURA BAR & KITCHEN ", "termsAcceptedAt": "2026-07-05T05:47:30.425Z"}	2026-07-05 11:17:30.433+05:30
566fa76a-7fb3-44bd-9fc0-788056aed9e2	14292123-33fc-4c0f-b583-c2e532fd6c2d	status_changed	admin@lunara.com	::ffff:165.99.175.242	{"reason": "Admin updated status to pending", "newStatus": "pending", "oldStatus": "pending_confirmation"}	2026-07-05 11:17:51.617+05:30
\.


--
-- Data for Name: venue_images; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.venue_images (id, venue_id, file_path, file_size, mime_type, image_type, caption, is_primary, display_order, uploaded_by, uploaded_at, created_at) FROM stdin;
70b49127-5719-4cc3-8bc9-28dde5d82fc3	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539430_bcc6e0faf7419c8a.compressed.webp	205280	image/webp	cover	\N	t	0	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:02.193+05:30	2026-06-16 17:19:02.193+05:30
8f483447-6fca-4153-ab71-a1ac37e249af	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539733_d7bfaaa8c7050d37.compressed.webp	8578	image/webp	interior	\N	f	1	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:02.234+05:30	2026-06-16 17:19:02.234+05:30
c954197d-7b03-4173-a240-6ee8c2b79cfa	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539741_e5689ab8e4ab5081.compressed.webp	9590	image/webp	interior	\N	f	2	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:02.268+05:30	2026-06-16 17:19:02.269+05:30
7cbf2f51-9bc2-41c6-896f-492fb87b55c0	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539749_c9ebb1c2d06d6e6f.compressed.webp	7808	image/webp	interior	\N	f	3	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:02.304+05:30	2026-06-16 17:19:02.304+05:30
c9f82868-41bc-499d-b5d4-eed28363e227	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539752_567c9499cf0f845e.compressed.webp	4912	image/webp	interior	\N	f	4	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:02.335+05:30	2026-06-16 17:19:02.335+05:30
8e58601d-3ec1-49dc-ad73-aed1c39366aa	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539768_3ec36bcd3bae1a5b.compressed.webp	6574	image/webp	interior	\N	f	5	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:02.366+05:30	2026-06-16 17:19:02.366+05:30
46c6bd6a-f3a8-4f48-ba67-12ddca3cefa0	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539769_a9a725b5a348ebfb.compressed.webp	78372	image/webp	interior	\N	f	6	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:02.768+05:30	2026-06-16 17:19:02.768+05:30
4ac7790a-e15d-4aef-bfcd-de48b9dad3f2	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539827_2bf9ccabe14a4eae.compressed.webp	11958	image/webp	interior	\N	f	7	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:02.809+05:30	2026-06-16 17:19:02.809+05:30
61ea5d44-42c8-42fd-a8ff-d207bfd490b0	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539848_3b03853c3aba8a8a.compressed.webp	12842	image/webp	interior	\N	f	8	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:02.847+05:30	2026-06-16 17:19:02.847+05:30
baaac885-dba2-4b52-8ee8-de779eb7543d	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539849_80b20fbb1489bf89.compressed.webp	6088	image/webp	interior	\N	f	9	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:02.882+05:30	2026-06-16 17:19:02.883+05:30
23d93eda-20e9-499d-99a0-fde4fe39ee4c	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539851_e7e769367aefa611.compressed.webp	14114	image/webp	interior	\N	f	10	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:02.921+05:30	2026-06-16 17:19:02.921+05:30
566d7fac-11bd-4f1a-9fb8-c04816cb3f06	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539870_776a08481e60f863.compressed.webp	7250	image/webp	interior	\N	f	11	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:02.953+05:30	2026-06-16 17:19:02.954+05:30
ae5e1f00-5567-4066-9ab6-eaffe226cb24	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539872_0803400e76e4ffca.compressed.webp	10194	image/webp	interior	\N	f	12	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:03.003+05:30	2026-06-16 17:19:03.003+05:30
aea9acf1-24cd-4ad9-adcb-cf552dbbd846	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539882_818b5bcc05cbbf2c.compressed.webp	18638	image/webp	interior	\N	f	13	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:03.061+05:30	2026-06-16 17:19:03.061+05:30
82d34a2a-5956-48f5-931f-946384744a34	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539892_5b442971686a8682.compressed.webp	17402	image/webp	interior	\N	f	14	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:03.114+05:30	2026-06-16 17:19:03.115+05:30
7845795e-a9ae-4695-a840-71fa2592fc6a	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539907_1470cc12732fce49.compressed.webp	9306	image/webp	interior	\N	f	15	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:03.173+05:30	2026-06-16 17:19:03.173+05:30
577e458f-8d9e-4db9-88e0-4dca93214689	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539924_e5bf8b432c6478b1.compressed.webp	24654	image/webp	food_menu	\N	f	1	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:03.633+05:30	2026-06-16 17:19:03.634+05:30
acfc0853-8ce9-4fb6-8f8e-56f606c1fe9f	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610539955_23f0917c01cbb699.compressed.webp	321226	image/webp	food_menu	\N	f	2	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:04.565+05:30	2026-06-16 17:19:04.565+05:30
72392152-3641-4a33-9083-9bbb84e31f34	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610540260_8a63fe0ae190d566.compressed.webp	297446	image/webp	food_menu	\N	f	3	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:05.456+05:30	2026-06-16 17:19:05.456+05:30
00c0d180-49ef-487d-ac62-8d32e1a00cb7	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610540492_52e5d9858c888dd9.compressed.webp	285718	image/webp	food_menu	\N	f	4	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:06.342+05:30	2026-06-16 17:19:06.342+05:30
804b8a08-1bd3-407b-aa1b-9a9027c640e4	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610540658_8e9d4024b2cbb9b5.compressed.webp	312966	image/webp	food_menu	\N	f	5	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:07.244+05:30	2026-06-16 17:19:07.244+05:30
5ecdc662-7331-408d-9125-7b346b762bc6	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610540821_183b95ed256b5bc6.compressed.webp	307296	image/webp	food_menu	\N	f	6	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:08.156+05:30	2026-06-16 17:19:08.156+05:30
a6ab090c-7531-42bf-a51b-bbe7a688d5b2	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610541043_8c0cf76f6f5214a2.compressed.webp	16594	image/webp	bar_menu	\N	f	1	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:08.586+05:30	2026-06-16 17:19:08.586+05:30
9fa00e65-be3c-4227-b4aa-856f856552e6	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610541074_42697e2b1020744c.compressed.webp	77446	image/webp	bar_menu	\N	f	2	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:09.067+05:30	2026-06-16 17:19:09.067+05:30
46b4fcbd-5a4b-4f3e-bf92-e1e926b4351d	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610541165_c07bb854db3c5bba.compressed.webp	78908	image/webp	bar_menu	\N	f	3	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:09.598+05:30	2026-06-16 17:19:09.598+05:30
9a909832-58c6-485d-9df8-37279a0ab8c9	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610541239_3d71293881fda27e.compressed.webp	64882	image/webp	bar_menu	\N	f	4	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:10.133+05:30	2026-06-16 17:19:10.133+05:30
4f9147f3-fc70-4885-a0cb-093dcf3b6e71	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610541281_c5fbf814c3685c85.compressed.webp	78584	image/webp	bar_menu	\N	f	5	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:10.626+05:30	2026-06-16 17:19:10.626+05:30
d409d4c2-5c28-4074-88a2-758a36136a04	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610541323_ef18ec4f2f9895fd.compressed.webp	79696	image/webp	bar_menu	\N	f	6	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:11.121+05:30	2026-06-16 17:19:11.122+05:30
ae4dd360-82ff-45c1-981a-af8465fe4a9d	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610541373_91dc617d7665a5a8.compressed.webp	53642	image/webp	bar_menu	\N	f	7	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:11.724+05:30	2026-06-16 17:19:11.724+05:30
49667ef6-dea1-4e38-a96f-6b7ebb602cc0	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610541406_1495a5a5b89f6e95.compressed.webp	65182	image/webp	bar_menu	\N	f	8	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:12.195+05:30	2026-06-16 17:19:12.195+05:30
c5694a98-5d92-4993-b8d0-2d1456d2f874	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610541460_3a2e295562fc6842.compressed.webp	67010	image/webp	bar_menu	\N	f	9	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:12.7+05:30	2026-06-16 17:19:12.7+05:30
d39e36c4-73cf-44fe-8b27-89a2f21faef5	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610541527_3fa21fce962b1e12.compressed.webp	91972	image/webp	bar_menu	\N	f	10	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:13.205+05:30	2026-06-16 17:19:13.205+05:30
b3d94d82-0eb3-42d6-a74f-84d88e39079b	4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	uploads\\venues\\4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e\\raw\\1781610541595_8138bcd0ef84cf6c.compressed.webp	64882	image/webp	bar_menu	\N	f	11	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 17:19:13.693+05:30	2026-06-16 17:19:13.694+05:30
1a0e13cd-fbeb-440c-ad52-bc511a2236d9	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781616475619_16c66c2076ef55d5.compressed.webp	643736	image/webp	cover	\N	t	0	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 18:58:32.817+05:30	2026-06-16 18:58:32.818+05:30
dfad72b8-06f3-474b-9a66-3bb771f4cf0b	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781616478308_fb84fe5055d19cdb.compressed.webp	149230	image/webp	interior	\N	f	1	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 18:58:33.316+05:30	2026-06-16 18:58:33.317+05:30
0d6421b9-0a6c-42a4-b02e-f3e4b4b96a85	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617330904_b5a38b1e4679aa42.compressed.webp	551548	image/webp	interior	\N	f	2	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:12:56.699+05:30	2026-06-16 19:12:56.699+05:30
7d3b16cb-af6e-45fc-9e4f-5ec9a1a752b8	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617331078_71b2d0caa851ac8b.compressed.webp	469722	image/webp	interior	\N	f	3	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:13:35.983+05:30	2026-06-16 19:13:35.984+05:30
37691bdc-6e67-49b4-8928-2ba49df25568	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617331298_770da00e2b3f1d6f.compressed.webp	636116	image/webp	interior	\N	f	4	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:13:40.45+05:30	2026-06-16 19:13:40.45+05:30
48ae5c20-6651-4ee3-b322-c87be24db47c	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617331495_1090beeaba4c1b06.compressed.webp	604038	image/webp	interior	\N	f	5	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:14:19.253+05:30	2026-06-16 19:14:19.253+05:30
c8e6250a-2363-411f-9c11-595e6a48c590	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617331759_1a840db9cfca8ab4.compressed.webp	662576	image/webp	interior	\N	f	6	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:14:23.779+05:30	2026-06-16 19:14:23.779+05:30
48b8c8f8-5981-4beb-9f35-7568ef651ce8	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617331946_c5c9320dca02cac8.compressed.webp	706706	image/webp	interior	\N	f	7	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:14:28.759+05:30	2026-06-16 19:14:28.759+05:30
0e5e2029-ea08-4dd7-8599-b4aea80fd5d2	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617332109_3a09e739f7022c3c.compressed.webp	608408	image/webp	interior	\N	f	8	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:15:11.504+05:30	2026-06-16 19:15:11.505+05:30
24111910-dbac-4b3d-9217-faa01748ab9e	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617332320_f66159ee52d592dc.compressed.webp	468842	image/webp	interior	\N	f	9	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:15:51.8+05:30	2026-06-16 19:15:51.801+05:30
6f72cd09-7f7e-489d-aea6-b87c4b37ebc6	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617332556_00ce0f4b915144d3.compressed.webp	689516	image/webp	interior	\N	f	10	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:15:56.732+05:30	2026-06-16 19:15:56.732+05:30
6c67df26-62e5-45dd-a864-17ad77ce828d	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617332733_d45cc15cb66a4560.compressed.webp	603638	image/webp	interior	\N	f	11	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:23:24.716+05:30	2026-06-16 19:23:24.717+05:30
19aac146-a0ba-48f1-b84f-6e39755bf8ff	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617333002_c35cb0d4aa2ce35d.compressed.webp	305104	image/webp	interior	\N	f	12	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:24:01.869+05:30	2026-06-16 19:24:01.869+05:30
d4d07b87-6009-4c98-8357-eb563fcaf4ae	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617333223_a696dec8f4b514ba.compressed.webp	891462	image/webp	interior	\N	f	13	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:24:48.961+05:30	2026-06-16 19:24:48.962+05:30
ce2a2893-14de-47c5-8bd5-d7db6f2f33e5	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617333591_c13c1df1d965fa0b.compressed.webp	567198	image/webp	interior	\N	f	14	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:30.222+05:30	2026-06-16 19:25:30.223+05:30
61d5b790-53e6-4c2a-9014-7e4ffe53e818	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617333809_84d9d36c2e0a132f.compressed.webp	41090	image/webp	food_menu	\N	f	1	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:30.783+05:30	2026-06-16 19:25:30.783+05:30
df349457-6412-4f5e-92d4-c2fbc0b34d85	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617333841_4bb6353d84f34bb4.compressed.webp	76872	image/webp	food_menu	\N	f	2	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:31.46+05:30	2026-06-16 19:25:31.46+05:30
4627bf51-94ae-4ae8-9d0a-1fc57b23dafa	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617333877_12df2594baa3c955.compressed.webp	85610	image/webp	food_menu	\N	f	3	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:32.113+05:30	2026-06-16 19:25:32.113+05:30
d37c28ef-803d-4d3b-b4da-4d3ea385dd36	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617333928_e0627fa5ae9edc9e.compressed.webp	79312	image/webp	food_menu	\N	f	4	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:32.709+05:30	2026-06-16 19:25:32.709+05:30
c54e0443-d02f-4b6d-9de1-8ebfc3744cf0	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617333967_53448c8bc07da8e7.compressed.webp	71646	image/webp	food_menu	\N	f	5	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:33.248+05:30	2026-06-16 19:25:33.248+05:30
d0f26d4e-018f-4680-9e6f-a73c6755ab80	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334023_e9c7d6a5991506b0.compressed.webp	94298	image/webp	food_menu	\N	f	6	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:33.861+05:30	2026-06-16 19:25:33.861+05:30
5a14e02e-5214-4647-8d1e-42ad3a091f8b	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334090_b232b302550161b7.compressed.webp	84306	image/webp	food_menu	\N	f	7	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:34.451+05:30	2026-06-16 19:25:34.451+05:30
fff4302b-d3af-4fbb-bcdb-549072c92f6d	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334157_0e9c67f5985ada5b.compressed.webp	85570	image/webp	food_menu	\N	f	8	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:35.028+05:30	2026-06-16 19:25:35.028+05:30
4e0ac4e3-c6e4-4d96-bad8-0361e3db2c35	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334223_9858c0d2b505c20c.compressed.webp	71350	image/webp	food_menu	\N	f	9	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:35.704+05:30	2026-06-16 19:25:35.704+05:30
535e8007-83b2-4d57-8e27-27b76a25dd29	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334297_59c193ea741c66c7.compressed.webp	79648	image/webp	food_menu	\N	f	10	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:36.33+05:30	2026-06-16 19:25:36.33+05:30
899f6b16-ebaf-4786-817b-0da0d365f631	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334364_5e742231e6704319.compressed.webp	85544	image/webp	food_menu	\N	f	11	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:37.013+05:30	2026-06-16 19:25:37.013+05:30
8e2fce8f-9f2e-4f4a-8a2d-a67237328c5a	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334439_0186bcc985b5d4d1.compressed.webp	78396	image/webp	food_menu	\N	f	12	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:37.581+05:30	2026-06-16 19:25:37.581+05:30
21c7780c-4b22-45cb-a5ff-10bdd6974d08	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334493_5a4ea461df68e837.compressed.webp	50554	image/webp	food_menu	\N	f	13	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:38.105+05:30	2026-06-16 19:25:38.106+05:30
bbad1024-c716-4571-911f-093919101dab	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334526_f171785776ecc9f1.compressed.webp	36226	image/webp	food_menu	\N	f	14	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:38.64+05:30	2026-06-16 19:25:38.64+05:30
3157001a-7138-4faf-a40b-882b12bec5ab	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334553_5cb0bd29e01813d8.compressed.webp	41202	image/webp	food_menu	\N	f	15	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:39.225+05:30	2026-06-16 19:25:39.225+05:30
4d1f3dc1-24a5-4b34-8cf1-758d3d4292b6	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334596_34212faf59207630.compressed.webp	106652	image/webp	bar_menu	\N	f	1	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:39.878+05:30	2026-06-16 19:25:39.878+05:30
18718d4d-672f-4429-ad90-cfa2cc9b96e4	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334677_0806cfd0e2db6b00.compressed.webp	95788	image/webp	bar_menu	\N	f	2	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:40.507+05:30	2026-06-16 19:25:40.507+05:30
51252598-b80e-455b-8b98-5e2076bf15bd	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334760_1020201d0925de8d.compressed.webp	82556	image/webp	bar_menu	\N	f	3	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:41.133+05:30	2026-06-16 19:25:41.133+05:30
ef60ac26-174d-4fb8-905d-7c5700c3e223	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334816_f5f6993494a0819a.compressed.webp	105016	image/webp	bar_menu	\N	f	4	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:41.744+05:30	2026-06-16 19:25:41.745+05:30
b378a740-7ea4-4767-b70a-49066ea31082	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334876_eb7d665eb2606e5a.compressed.webp	100246	image/webp	bar_menu	\N	f	5	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:42.319+05:30	2026-06-16 19:25:42.32+05:30
273aedad-4385-4ad7-95f7-268c24107f07	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334930_17c61cce18f12b6a.compressed.webp	72346	image/webp	bar_menu	\N	f	6	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:42.886+05:30	2026-06-16 19:25:42.886+05:30
8809ae74-57a5-47ce-9740-13ea32804bfc	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617334984_5e328ad23899fa12.compressed.webp	78484	image/webp	bar_menu	\N	f	7	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:43.543+05:30	2026-06-16 19:25:43.543+05:30
5cd331bd-b845-429a-ae80-26c47bcb3140	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617335034_38a217882db42399.compressed.webp	97356	image/webp	bar_menu	\N	f	8	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:44.227+05:30	2026-06-16 19:25:44.227+05:30
5da54e01-5e41-4a47-a04a-206d1efbdb40	17887092-ea6a-4102-82a0-06aefdb1d79d	uploads\\venues\\17887092-ea6a-4102-82a0-06aefdb1d79d\\raw\\1781617335093_a82855e6ce1d15bd.compressed.webp	96876	image/webp	bar_menu	\N	f	9	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-16 19:25:44.793+05:30	2026-06-16 19:25:44.793+05:30
f11cda6b-8ce4-44b2-8725-2fcee8c5a806	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782558186674_3ae54f07e0dcaaa7.compressed.webp	218078	image/webp	cover	\N	t	0	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:33:12.972+05:30	2026-06-27 16:33:12.973+05:30
a8e3a145-c6fb-4858-a210-3e33f1c9dd66	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782558188825_b275b086705747e8.compressed.webp	304864	image/webp	food_menu	\N	f	1	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:36:34.277+05:30	2026-06-27 16:36:34.277+05:30
528903ca-0419-4128-944c-3bb05777f8c3	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782558189002_84cca83eec237a2b.compressed.webp	271214	image/webp	food_menu	\N	f	2	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:36:35.026+05:30	2026-06-27 16:36:35.027+05:30
dcac3eca-ee7d-4386-bfa6-9237f24917fc	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782558187118_029fcf6a6b0a3a0f.compressed.webp	286014	image/webp	interior	\N	f	1	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:33:14.351+05:30	2026-06-27 16:33:14.351+05:30
645ac7d6-04aa-41ca-8cbb-1553854b034b	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782558187236_83a2911e3287094e.compressed.webp	468464	image/webp	interior	\N	f	2	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:34:06.94+05:30	2026-06-27 16:34:06.941+05:30
8e538d5e-44d6-4770-91a3-344cfaaee222	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782558187445_81232fba61720db5.compressed.webp	1565414	image/webp	interior	\N	f	3	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:35:20.316+05:30	2026-06-27 16:35:20.317+05:30
a9723890-231c-44ef-8d7a-2d7968d2d14f	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782558188032_dde92e935ccf3129.compressed.webp	1630738	image/webp	interior	\N	f	4	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:36:33.449+05:30	2026-06-27 16:36:33.45+05:30
04274f08-bcba-4868-9dc4-05e9f16549ff	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782558189166_d677a4ad216b3d79.compressed.webp	533640	image/webp	bar_menu	\N	f	1	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:36:39.356+05:30	2026-06-27 16:36:39.356+05:30
33e359aa-b571-4c08-8536-038f945fc93c	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782558189408_5f36fef9a253f44b.compressed.webp	542062	image/webp	bar_menu	\N	f	2	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:36:43.792+05:30	2026-06-27 16:36:43.792+05:30
0709ee5b-28ae-447b-9dc1-d00494526130	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782558189584_89700498a687b52d.compressed.webp	496716	image/webp	bar_menu	\N	f	3	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:36:48.243+05:30	2026-06-27 16:36:48.243+05:30
95f7b74a-2bd6-4023-8d8a-f2cc636bbfbf	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782558190471_ccf33acea97764a9.compressed.webp	529970	image/webp	bar_menu	\N	f	4	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:36:52.791+05:30	2026-06-27 16:36:52.791+05:30
752a3e1c-f132-4e8f-9320-1fb9f2db5eb1	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782558190943_691f00bbbb3862a8.compressed.webp	152064	image/webp	party_packages	\N	f	1	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:36:53.434+05:30	2026-06-27 16:36:53.434+05:30
ea31a8c3-a23b-4769-9217-3c085b9d6dc5	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782559368357_6286fdbeb638cfc2.compressed.webp	625216	image/webp	interior	\N	f	5	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:53:46.307+05:30	2026-06-27 16:53:46.308+05:30
5d3486bb-4682-4a52-8535-838959c982de	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782559368695_88403d212b4aa4f9.compressed.webp	767146	image/webp	interior	\N	f	6	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:54:38.142+05:30	2026-06-27 16:54:38.143+05:30
fcf8ea1c-77c0-4880-b0eb-ecbf9a57565e	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782559369010_8bf304ad500ac0f7.compressed.webp	494260	image/webp	interior	\N	f	7	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:55:26.275+05:30	2026-06-27 16:55:26.276+05:30
290cf9ae-2d17-4a52-a443-780abc5e51ee	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782559369408_db74258db117ffd6.compressed.webp	652420	image/webp	interior	\N	f	8	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:56:22.379+05:30	2026-06-27 16:56:22.38+05:30
ff6ad71f-e13c-47e0-85ed-18afa1054e94	b50d85dd-ef32-4753-9e53-159ac11d8046	uploads\\venues\\b50d85dd-ef32-4753-9e53-159ac11d8046\\raw\\1782562902611_e19a564b70de69fc.compressed.webp	295508	image/webp	cover	\N	t	0	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 17:51:46.362+05:30	2026-06-27 17:51:46.363+05:30
07e1c297-9608-4ec5-b73b-ca500eeeac88	b50d85dd-ef32-4753-9e53-159ac11d8046	uploads\\venues\\b50d85dd-ef32-4753-9e53-159ac11d8046\\raw\\1782562903090_12dc0a6b0307f66f.compressed.webp	418110	image/webp	interior	\N	f	1	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 17:51:47.531+05:30	2026-06-27 17:51:47.531+05:30
108a5b55-0375-41d0-911e-57be45f6ebdc	b50d85dd-ef32-4753-9e53-159ac11d8046	uploads\\venues\\b50d85dd-ef32-4753-9e53-159ac11d8046\\raw\\1782562903238_9467b85a9d0a9773.compressed.webp	394914	image/webp	interior	\N	f	2	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 17:51:48.663+05:30	2026-06-27 17:51:48.663+05:30
3c24bd56-9689-4356-a9a5-48ae6361dd69	b50d85dd-ef32-4753-9e53-159ac11d8046	uploads\\venues\\b50d85dd-ef32-4753-9e53-159ac11d8046\\raw\\1782562903379_57668c413e7a76ec.compressed.webp	388424	image/webp	interior	\N	f	3	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 17:51:49.769+05:30	2026-06-27 17:51:49.769+05:30
db59da44-ad5b-4758-9a82-0da837607bff	b50d85dd-ef32-4753-9e53-159ac11d8046	uploads\\venues\\b50d85dd-ef32-4753-9e53-159ac11d8046\\raw\\1782562903513_881667b6e0132887.compressed.webp	439748	image/webp	interior	\N	f	4	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 17:51:50.906+05:30	2026-06-27 17:51:50.906+05:30
6b43cdf6-06da-495d-b142-2d62ab5afb78	b50d85dd-ef32-4753-9e53-159ac11d8046	uploads\\venues\\b50d85dd-ef32-4753-9e53-159ac11d8046\\raw\\1782562903734_b82d1b3c2da7f0ba.compressed.webp	496980	image/webp	interior	\N	f	5	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 17:51:52.115+05:30	2026-06-27 17:51:52.115+05:30
6a3e6830-7224-403d-8c5a-497a2a731a94	b50d85dd-ef32-4753-9e53-159ac11d8046	uploads\\venues\\b50d85dd-ef32-4753-9e53-159ac11d8046\\raw\\1782562903918_e0d64655bccc2a69.compressed.webp	253466	image/webp	interior	\N	f	6	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 17:51:53.236+05:30	2026-06-27 17:51:53.236+05:30
157a9636-98e7-45c5-be67-bbd22e48b49b	b50d85dd-ef32-4753-9e53-159ac11d8046	uploads\\venues\\b50d85dd-ef32-4753-9e53-159ac11d8046\\raw\\1782562904083_ebad05fb10b4030b.compressed.webp	267782	image/webp	interior	\N	f	7	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 17:51:54.403+05:30	2026-06-27 17:51:54.403+05:30
c6593460-6948-40e9-b2e6-a246f0da43c3	b50d85dd-ef32-4753-9e53-159ac11d8046	uploads\\venues\\b50d85dd-ef32-4753-9e53-159ac11d8046\\raw\\1782562904250_e14981725b0b6c12.compressed.webp	262496	image/webp	interior	\N	f	8	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 17:51:55.445+05:30	2026-06-27 17:51:55.446+05:30
04e50403-f497-4e5e-9fbb-256708589cbc	b50d85dd-ef32-4753-9e53-159ac11d8046	uploads\\venues\\b50d85dd-ef32-4753-9e53-159ac11d8046\\raw\\1782563312184_970ad62c0e92ed88.compressed.webp	166822	image/webp	food_menu	\N	f	1	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 17:58:33.832+05:30	2026-06-27 17:58:33.833+05:30
333a2cfa-b768-4248-89ae-474df889872d	b50d85dd-ef32-4753-9e53-159ac11d8046	uploads\\venues\\b50d85dd-ef32-4753-9e53-159ac11d8046\\raw\\1782563312341_17b9627a96458e60.compressed.webp	206718	image/webp	food_menu	\N	f	2	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 17:58:34.559+05:30	2026-06-27 17:58:34.56+05:30
c2f22c7e-8eed-4e3f-96dc-68a45fc428f1	b50d85dd-ef32-4753-9e53-159ac11d8046	uploads\\venues\\b50d85dd-ef32-4753-9e53-159ac11d8046\\raw\\1782563312496_e9c6c300a38c5d98.compressed.webp	190084	image/webp	food_menu	\N	f	3	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 17:58:35.301+05:30	2026-06-27 17:58:35.301+05:30
f03e1e84-8329-4799-8719-dfa1e7c5d784	b50d85dd-ef32-4753-9e53-159ac11d8046	uploads\\venues\\b50d85dd-ef32-4753-9e53-159ac11d8046\\raw\\1782563312670_4ee089414bcb0521.compressed.webp	188252	image/webp	food_menu	\N	f	4	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 17:58:36.043+05:30	2026-06-27 17:58:36.044+05:30
786e8bd1-496f-468d-ba32-7aa28dbbf64f	b50d85dd-ef32-4753-9e53-159ac11d8046	uploads\\venues\\b50d85dd-ef32-4753-9e53-159ac11d8046\\raw\\1782563312801_b871e4036f79ecfd.compressed.webp	205106	image/webp	food_menu	\N	f	5	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 17:58:36.763+05:30	2026-06-27 17:58:36.763+05:30
85dc3c1d-cb33-4696-a2c0-8d47998ea555	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782559065068_e752bf511f38efd8.compressed.webp	627878	image/webp	interior	\N	f	10	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:55:12.918+05:30	2026-06-27 16:55:12.918+05:30
28c2182e-7d15-46e6-8316-7f1ebd985d88	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782559065473_4936a64cfe1f60a6.compressed.webp	15474	image/webp	interior	\N	f	11	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:55:12.96+05:30	2026-06-27 16:55:12.96+05:30
75291e41-5fe0-4cd9-9601-bc79b59619c8	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782559065474_dec1f2b35af739f3.compressed.webp	10086	image/webp	interior	\N	f	12	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:55:12.991+05:30	2026-06-27 16:55:12.991+05:30
b57ca8de-9da5-44de-827d-9868fb06be93	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782559065476_6c4fa0e2097cc78c.compressed.webp	13052	image/webp	interior	\N	f	13	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:55:13.028+05:30	2026-06-27 16:55:13.028+05:30
2024fdd4-dc68-484f-a386-881f359c78d3	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782559064239_fc7d06fc5498b593.compressed.webp	939244	image/webp	interior	\N	f	9	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:53:29.759+05:30	2026-06-27 16:53:29.76+05:30
89b022e8-8a75-4b20-b802-255cbb5eae8c	a34456dc-fc25-4092-aae8-d3f8fd29d76f	uploads\\venues\\a34456dc-fc25-4092-aae8-d3f8fd29d76f\\raw\\1782559065484_324c75dc7da5f0ec.compressed.webp	13516	image/webp	interior	\N	f	14	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 16:55:13.065+05:30	2026-06-27 16:55:13.065+05:30
60f67e23-8839-4f53-8157-a3310df0d953	b50d85dd-ef32-4753-9e53-159ac11d8046	uploads\\venues\\b50d85dd-ef32-4753-9e53-159ac11d8046\\raw\\1782563312928_87b54ff1fa2a60d2.compressed.webp	139692	image/webp	food_menu	\N	f	6	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-27 17:58:37.43+05:30	2026-06-27 17:58:37.431+05:30
765e781e-b791-44d6-8ce4-6b9a215f1d3a	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624100549_5b1aff79d04df212.compressed.webp	142298	image/webp	cover	\N	t	0	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:51:42.435+05:30	2026-06-28 10:51:42.435+05:30
1a606a4d-fb10-4f26-bc7e-fdb9654f7df8	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624100749_8edc2fbfb4f600e2.compressed.webp	372058	image/webp	interior	\N	f	1	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:51:47.805+05:30	2026-06-28 10:51:47.805+05:30
dddbffae-38e0-4cb3-809f-74b95f747e90	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624100856_99e0957cd98e5f83.compressed.webp	367316	image/webp	interior	\N	f	2	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:51:49.266+05:30	2026-06-28 10:51:49.266+05:30
b770a1ac-a844-435e-9be7-ef2a379b5954	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624100978_57731bb46a89194f.compressed.webp	302618	image/webp	interior	\N	f	3	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:51:50.196+05:30	2026-06-28 10:51:50.196+05:30
13c22993-ad69-4bd2-8a17-f8c8390aedab	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624101076_b9a4860265b4e4e6.compressed.webp	870090	image/webp	interior	\N	f	4	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:52:51.425+05:30	2026-06-28 10:52:51.426+05:30
91d16890-b477-4a46-9876-8114e70f03b0	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624101329_5061fbb2bd3eda99.compressed.webp	716264	image/webp	interior	\N	f	5	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:52:57.581+05:30	2026-06-28 10:52:57.582+05:30
8b5e9f71-162e-426b-bd5a-67d8419f32b5	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624101419_fcfb1c014c21d963.compressed.webp	314454	image/webp	interior	\N	f	6	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:53:00.233+05:30	2026-06-28 10:53:00.233+05:30
515e7c8a-7137-4dad-9ff2-14fe7a3ba352	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624101511_bba5893c33b242e0.compressed.webp	87244	image/webp	interior	\N	f	7	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:53:00.715+05:30	2026-06-28 10:53:00.716+05:30
c0cd8a82-b436-4ea3-b573-c8723cc277df	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624101541_4becc31ecce753c7.compressed.webp	164990	image/webp	interior	\N	f	8	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:53:01.204+05:30	2026-06-28 10:53:01.204+05:30
3d2570a0-2fd0-4e92-b116-616c830b9563	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624101594_7565c3aaee129144.compressed.webp	245334	image/webp	interior	\N	f	9	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:53:01.778+05:30	2026-06-28 10:53:01.778+05:30
c9003252-698e-4294-97e6-efc0432a517f	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624101677_3203ec228e2edee7.compressed.webp	190628	image/webp	interior	\N	f	10	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:53:02.295+05:30	2026-06-28 10:53:02.295+05:30
12f2fcc2-33d4-43bf-a1c8-3b7acb4fc81f	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624101749_5d9120df6792102a.compressed.webp	45040	image/webp	interior	\N	f	11	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:53:02.692+05:30	2026-06-28 10:53:02.692+05:30
352c5425-b9dd-4bcb-a44b-0d81ca3ecfe5	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624101768_42bf51ac037411af.compressed.webp	134434	image/webp	interior	\N	f	12	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:53:03.118+05:30	2026-06-28 10:53:03.118+05:30
0ac0b9e3-935b-41d2-915d-2f47c4828fad	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624101811_423640a0832c29ee.compressed.webp	185260	image/webp	interior	\N	f	13	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:53:03.622+05:30	2026-06-28 10:53:03.622+05:30
573a6a1d-8679-4c08-ac72-7f537e944e59	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624101901_a253181ff80825dc.compressed.webp	165010	image/webp	interior	\N	f	14	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:53:04.098+05:30	2026-06-28 10:53:04.098+05:30
779be43f-e9cf-48e4-98e4-0df8d38d5e40	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624476378_6e83f554622e1d98.compressed.webp	226674	image/webp	party_packages	\N	f	1	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:57:58.85+05:30	2026-06-28 10:57:58.85+05:30
2ab56e33-96d9-416f-88dc-7bd42de886b1	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624476504_a295aea3f7ddf3b5.compressed.webp	275886	image/webp	party_packages	\N	f	2	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:58:00.094+05:30	2026-06-28 10:58:00.094+05:30
e95fee60-cdf2-4ffd-b28b-78aff5af52ce	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624476647_7884dc393377b205.compressed.webp	246866	image/webp	party_packages	\N	f	3	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:58:01.283+05:30	2026-06-28 10:58:01.283+05:30
d11de102-0215-4f2b-8191-9ac8881b47d5	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624476748_73e35320d92182ce.compressed.webp	304276	image/webp	party_packages	\N	f	4	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:58:02.487+05:30	2026-06-28 10:58:02.488+05:30
7279251e-9522-4498-9a76-6872a733b859	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624476850_a61b046056847d54.compressed.webp	258732	image/webp	party_packages	\N	f	5	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:58:03.677+05:30	2026-06-28 10:58:03.677+05:30
f5608922-6ea7-4416-9278-9c91d16a65c5	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624477037_92498f39f4478d11.compressed.webp	322110	image/webp	party_packages	\N	f	6	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:58:04.942+05:30	2026-06-28 10:58:04.942+05:30
c7a89fa4-b461-4ab3-83eb-e53b10b49a4a	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624477185_2a440263dee3ff70.compressed.webp	266566	image/webp	party_packages	\N	f	7	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:58:06.168+05:30	2026-06-28 10:58:06.168+05:30
59cfaa73-37c1-49bd-9982-40f2b46e29cd	4311111f-8e89-4016-a39c-faf3d12eacf9	uploads\\venues\\4311111f-8e89-4016-a39c-faf3d12eacf9\\raw\\1782624477307_b509114d1220fdc6.compressed.webp	312520	image/webp	party_packages	\N	f	8	681a88ab-5628-4081-af04-22aeb74daef2	2026-06-28 10:58:07.437+05:30	2026-06-28 10:58:07.437+05:30
0655ba72-df2b-4f01-8480-a75e0eec933d	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019054961_136faebdc2c518a0.compressed.webp	217286	image/webp	interior	\N	f	1	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:17.362+05:30	2026-07-03 00:34:17.362+05:30
ced91dc1-7156-4337-aa6f-cbeed9725a16	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019055108_1e6ed1e02bf55696.compressed.webp	159402	image/webp	interior	\N	f	2	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:17.738+05:30	2026-07-03 00:34:17.739+05:30
cbbf4b3b-443a-4c93-91da-efe502c9a95b	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019055223_3829d506892d7944.compressed.webp	59504	image/webp	interior	\N	f	3	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:17.994+05:30	2026-07-03 00:34:17.994+05:30
ee0f5547-51bd-4c3d-99a6-68da2a64230a	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019055271_5eeee51e279f973a.compressed.webp	207056	image/webp	interior	\N	f	4	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:18.545+05:30	2026-07-03 00:34:18.545+05:30
7abbcb3f-4eca-499b-a99c-0df7958590b4	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019055391_0e575194155c7c5a.compressed.webp	66136	image/webp	interior	\N	f	5	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:18.841+05:30	2026-07-03 00:34:18.841+05:30
93117f13-7d79-4ebc-8215-48771a02181e	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019055441_b4751f5f6cef40f3.compressed.webp	60912	image/webp	interior	\N	f	6	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:19.133+05:30	2026-07-03 00:34:19.133+05:30
ac127d64-4659-4d53-9d09-97c536a3a0ad	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019055471_1d49619d23fcce8f.compressed.webp	52624	image/webp	interior	\N	f	7	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:19.388+05:30	2026-07-03 00:34:19.388+05:30
38b1aeeb-5354-429d-b192-917a5c629f12	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019055516_35df137fa8babf0c.compressed.webp	63118	image/webp	interior	\N	f	8	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:19.642+05:30	2026-07-03 00:34:19.642+05:30
c2cfc49c-b5c0-428b-8228-b092f618714d	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019055566_fb53722353a418a5.compressed.webp	157512	image/webp	interior	\N	f	9	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:20.117+05:30	2026-07-03 00:34:20.117+05:30
00a409b4-27b4-4235-8246-978aa94a3c26	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019055712_381fa2d63cd8e3b1.compressed.webp	127218	image/webp	interior	\N	f	10	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:20.515+05:30	2026-07-03 00:34:20.515+05:30
47127c23-a741-4045-bee5-b3f43c91da9c	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019055831_c75e242c869390db.compressed.webp	124130	image/webp	interior	\N	f	11	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:20.854+05:30	2026-07-03 00:34:20.854+05:30
c1fb4a13-5bda-4bd7-ba2b-fad90fb98bb6	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019055916_55d36fd40981dcbe.compressed.webp	89176	image/webp	interior	\N	f	12	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:21.158+05:30	2026-07-03 00:34:21.158+05:30
f90331e3-16d4-4f20-a8c7-80057d22b2e1	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019055982_adc40d84281839f0.compressed.webp	101612	image/webp	interior	\N	f	13	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:21.489+05:30	2026-07-03 00:34:21.489+05:30
068ce983-7686-4484-ab43-318934e8244a	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019056055_42b54a1ce5cf07ea.compressed.webp	139572	image/webp	interior	\N	f	14	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:21.831+05:30	2026-07-03 00:34:21.831+05:30
28b924ab-768e-4793-9fd0-ba2a10122969	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019056146_3dc9ae44e70bd3df.compressed.webp	60734	image/webp	interior	\N	f	15	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:22.11+05:30	2026-07-03 00:34:22.11+05:30
9020a5b9-8df9-4b62-b049-14fdef8a0657	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019056191_715a7e1588ad8106.compressed.webp	68738	image/webp	interior	\N	f	16	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:22.349+05:30	2026-07-03 00:34:22.35+05:30
6ea5ee54-e0b6-4b9d-8791-e81f6e9d22bb	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019056231_83ac4877b5cf734b.compressed.webp	69980	image/webp	interior	\N	f	17	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:22.647+05:30	2026-07-03 00:34:22.648+05:30
87783d36-1f9e-4f2a-8bdf-23fe6bb02e7a	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019056271_d9b721ab6bdcc71f.compressed.webp	161592	image/webp	interior	\N	f	18	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:23.01+05:30	2026-07-03 00:34:23.01+05:30
2e70351a-4db4-4a47-8e75-9116b2602f21	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019056363_7bdba1939889b30d.compressed.webp	67824	image/webp	interior	\N	f	19	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:23.302+05:30	2026-07-03 00:34:23.302+05:30
121b35af-7e58-467a-9acd-69a927bb1d37	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019056406_230b5e3adf86a572.compressed.webp	94440	image/webp	interior	\N	f	20	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:34:23.564+05:30	2026-07-03 00:34:23.564+05:30
1dbda06c-d84d-444e-893f-31c21fd84b7e	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783019606937_c6b5d7eb48d3d056.compressed.webp	179610	image/webp	cover	\N	t	0	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:43:28.177+05:30	2026-07-03 00:43:28.178+05:30
fd236b85-26d3-4726-8229-78d029b6baac	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783020357267_268ac7ea6a569af9.compressed.webp	28242	image/webp	bar_menu	\N	f	1	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:55:59.07+05:30	2026-07-03 00:55:59.07+05:30
29d29eaf-2313-4231-8593-cfa479301b54	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783020357587_d42cc276642391ef.compressed.webp	585646	image/webp	bar_menu	\N	f	2	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:56:01.441+05:30	2026-07-03 00:56:01.442+05:30
93cfc3aa-7042-47e2-b5b7-ab88d5e40dce	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783020357869_00b0970cb00bbad5.compressed.webp	561578	image/webp	bar_menu	\N	f	3	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:56:03.726+05:30	2026-07-03 00:56:03.726+05:30
2b2699f5-7529-4a27-bb3e-a1611b5488db	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783020358144_9686f84e3e869450.compressed.webp	375430	image/webp	bar_menu	\N	f	4	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:56:05.428+05:30	2026-07-03 00:56:05.428+05:30
0ea2c215-4151-4f15-b424-3d1b5c46efc5	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783020358327_b69df6419c47d175.compressed.webp	426854	image/webp	bar_menu	\N	f	5	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:56:08.238+05:30	2026-07-03 00:56:08.238+05:30
54a8abe1-bafb-443c-b5b7-0c55fc8fefcd	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783020358492_abd328cb10d2fb81.compressed.webp	351728	image/webp	bar_menu	\N	f	6	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:56:10.923+05:30	2026-07-03 00:56:10.923+05:30
33d7d3a0-ec83-42cb-9a5a-cb65e358c53d	ab320228-2d2f-41da-9d07-c9f5a915211e	uploads\\venues\\ab320228-2d2f-41da-9d07-c9f5a915211e\\raw\\1783020358652_d0feb0b170f0d926.compressed.webp	364056	image/webp	bar_menu	\N	f	7	681a88ab-5628-4081-af04-22aeb74daef2	2026-07-03 00:56:13.393+05:30	2026-07-03 00:56:13.393+05:30
\.


--
-- Data for Name: venues; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.venues (id, owner_id, name, slug, tagline, description, category, tags, address_line1, address_line2, area, city, state, postal_code, country, latitude, longitude, display_order, nearest_landmark, directions, phone, mobile, whatsapp, email, website, instagram, facebook, cp_name, cp_designation, cp_mobile, cp_email, alt_cp_name, alt_cp_designation, alt_cp_mobile, alt_cp_email, capacity, seating_capacity, standing_capacity, opening_time, closing_time, days_open, age_limit, cover_charge_male, cover_charge_female, discount_percentage, table_booking_charges, group_party_charge_per_person, group_party_discount_percentage, couple_entry_fee, dress_code, cuisine_types, music_types, amenities, pan_number, gst_number, fssai_license, liquor_license, fire_safety_cert, trade_license, bank_account_number, bank_ifsc, bank_name, average_rating, total_reviews, status, terms_accepted_at, confirmation_token, confirmation_token_expires_at, owner_email_sent_at, owner_confirmed_at, featured, is_active, is_verified, is_premium, created_at, updated_at) FROM stdin;
4f9ceddb-9ab7-46dd-92a9-49e17cab4f4e	681a88ab-5628-4081-af04-22aeb74daef2	Tettoricca	tettoricca	premium rooftop lounge	🪙₹ 3100 for two                        \r\n🎟️ 50% discounts for Lunara Users\r\n🍽️ North Indian, Continental, Biryani, Pasta, Asian, Oriental, Pizza\r\n🍷 Full bar available\r\n📍4th Floor, Xion Mall, Near DMart, Hinjawadi, Pune	rooftop	["nightclub", "bar", "rooftop", "Dance Floor", "Pub", "Lounge"]	4th Floor, Xion Mall, Near DMart, Hinjawadi, Pune		Hinjewadi	Pune	Maharashtra	411057	India	18.59238500	73.74469300	1		4th Floor, Xion Mall, Near DMart, Hinjawadi, Pune		9975891999	9975891999	enquiry@ssklworld.com		tettoricca		Tettoricca		9975891999						150	100	150	12:00:00	12:00:00	["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]	21	0.00	0.00	50.00	0.00	0.00	0.00	0.00	Smart Casual	["Indian", "Continental", "Modern European", "Asian Fusion", "Asian", "Chinese", "Pub Grub", "Finger Food", "Italian", "Seafood", "Bombay Style", "Mediterranean", "Irish", "British"]	["House", "Techno", "Commercial", "EDM", "Deep House", "Lounge", "Chill", "Irish Folk", "Bollywood", "Retro", "Jukebox", "Hip-Hop", "Rock", "Pop", "Jazz", "Acoustic"]	{"hasAC": true, "hasDJ": true, "hasPool": true, "hasWifi": true, "hasParking": true, "hasRooftop": true, "hasLiveMusic": true, "hasDanceFloor": true, "hasHappyHours": false, "hasVIPSection": true, "hasSmokingZone": true, "hasValetParking": false, "hasBottleService": true, "hasPrivateDining": true, "hasOutdoorSeating": true}										0.00	0	live	\N	\N	\N	\N	2026-06-16 17:19:01.657+05:30	f	t	t	f	2026-06-16 17:19:01.642+05:30	2026-06-16 18:29:57.152+05:30
17887092-ea6a-4102-82a0-06aefdb1d79d	681a88ab-5628-4081-af04-22aeb74daef2	LOVA	lova	All Day Kitchen & Bar	🪙₹ 3100 for two                        \r\n🎟️ 50% discounts for Lunara Users\r\n🍽️ Biryani, Momos, North Indian, Chinese, Pizza, Beverages, Continental, Pasta\r\n🍷 Full bar available\r\n📍4th Floor, Sai Apex, Datta Mandir Chowk, Viman Nagar, Pune	bar	["nightclub", "bar", "rooftop", "Outdoor seating"]	4th Floor, Sai Apex, Datta Mandir Chowk, Viman Nagar, Pune	 	Viman Nagar	Pune	Maharashtra	411014	India	18.56486400	73.91428900	1	Sai Apex, Datta Mandir Chowk, Viman Nagar 	4th Floor, Sai Apex, Datta Mandir Chowk, Viman Nagar, Pune		9325529545		favelapune1997@gmail.com		lovapune		Mr.Amit	Manager	8208212661						150	100	150	04:00:00	01:30:00	["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]	21	2000.00	2000.00	50.00	0.00	0.00	0.00	0.00	Samrt Casual	["Indian", "Continental", "Asian", "Chinese", "Italian", "Goan", "Seafood", "Mediterranean", "Irish", "British", "Bombay Style", "Finger Food", "Pub Grub", "Asian Fusion", "Modern European"]	["EDM", "House", "Techno", "Deep House", "Lounge", "Chill", "Commercial", "Irish Folk", "Retro", "Bollywood", "Hip-Hop", "Jukebox", "Rock", "Pop", "Jazz", "Acoustic"]	{"hasAC": true, "hasDJ": true, "hasPool": false, "hasWifi": true, "hasParking": true, "hasRooftop": true, "hasLiveMusic": true, "hasDanceFloor": false, "hasHappyHours": true, "hasVIPSection": false, "hasSmokingZone": true, "hasValetParking": false, "hasBottleService": true, "hasPrivateDining": true, "hasOutdoorSeating": true}										0.00	0	live	2026-06-16 16:53:28.521+05:30	6b93c6505e2895799c7cf96267970f6717d284ae83f0066295c8f31893a7a156	2026-06-19 16:53:28.52+05:30	2026-06-16 16:53:30.937+05:30	\N	f	t	t	f	2026-06-16 16:53:28.497+05:30	2026-06-22 14:51:49.554+05:30
4311111f-8e89-4016-a39c-faf3d12eacf9	681a88ab-5628-4081-af04-22aeb74daef2	Echho	echho	Club | Kitchen | Bar	🪙₹ 3500 for two                        \r\n🎟️ Free Entry For Girls\r\n🍽️ Continental, North Indian, Chinese, Pizza, Fast Food, Biryani, Desserts, Bar Food\r\n🍷 Full bar available\r\n📍2nd Floor, The Social St, Hinjawadi, Pune, Maharashtra 411057	club	["nightclub", "pub", "bar", "club", "dance floor"]	2nd Floor, The Social St, Hinjawadi, Pune, Maharashtra 411057		Hinjewadi	Pune	Maharashtra	411057	India	18.59053900	73.74570000	0	The Social Street			9975437222	9975437222	echho.club@gmail.com		echho.pune		Mr. Sheel Kanani		8446440800						150	100	150	07:30:00	01:30:00	["Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]	21	2000.00	0.00	0.00	0.00	0.00	0.00	1000.00		[]	[]	{"hasAC": true, "hasDJ": true, "hasPool": false, "hasWifi": true, "hasParking": true, "hasRooftop": false, "hasLiveMusic": true, "hasDanceFloor": true, "hasHappyHours": false, "hasVIPSection": true, "hasSmokingZone": true, "hasValetParking": false, "hasBottleService": true, "hasPrivateDining": true, "hasOutdoorSeating": false}										0.00	0	live	2026-06-28 10:46:44.893+05:30	245ccf6123e5d20654b7feb5f66db68ad76b7141d4ac46e205c81b7b74f25243	2026-07-01 10:46:44.893+05:30	\N	\N	f	t	f	f	2026-06-28 10:46:44.868+05:30	2026-06-29 11:03:45.37+05:30
b50d85dd-ef32-4753-9e53-159ac11d8046	681a88ab-5628-4081-af04-22aeb74daef2	Cafe Vanabella	cafe-vanabella	Leafy vibes - Fresh bites - Pure bliss	🪙₹ 800 for two                        \r\n🎟️ 10% discounts for Lunara Users | Free Entry\r\n🍽️ Pizza, Pasta, Fast Food, Shake, Beverages\r\n📍3, GK Ln., near Srimal Hospital, Nandanwan Society, Vishal Nagar, Pimple Nilakh, Pune 411027	cafe	["Cafe", "Nature Office", "Coworking", "workshops"]	3, GK Ln., near Srimal Hospital, Nandanwan Society, Vishal Nagar, Pimple Nilakh, Pune 411027		Pune	Pune	Maharashtra	411027	India	18.58000200	73.78583300	0	Srimal Hospital, Nandanwan Society, Vishal Nagar, Pimple Nilakh			8262022502		cafevanabella@gmail.com	https://www.cafevanabella.com/	cafevanabella		Mr. Sushant		8262022502						100	70	100	11:00:00	10:00:00	["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]	18	0.00	0.00	10.00	0.00	0.00	0.00	0.00	No Strict Dress Code	["Indian", "Modern European", "Continental", "Asian", "Asian Fusion", "Pub Grub", "Chinese", "Italian", "Finger Food", "Goan", "Seafood", "Mediterranean", "Irish", "British", "Bombay Style"]	["EDM", "Deep House", "House", "Lounge", "Techno", "Chill", "Commercial", "Irish Folk", "Bollywood", "Retro", "Jukebox", "Hip-Hop", "Rock", "Jazz", "Pop", "Acoustic"]	{"hasAC": false, "hasDJ": false, "hasPool": false, "hasWifi": true, "hasParking": false, "hasRooftop": false, "hasLiveMusic": true, "hasDanceFloor": false, "hasHappyHours": false, "hasVIPSection": false, "hasSmokingZone": false, "hasValetParking": false, "hasBottleService": false, "hasPrivateDining": true, "hasOutdoorSeating": true}										0.00	0	live	2026-06-27 17:51:44.407+05:30	07418b4a3175c00005fdb55afa7dea0611686ac41b25c20ff1a1f365976553e9	2026-06-30 17:51:44.407+05:30	\N	\N	f	t	f	f	2026-06-27 17:51:44.385+05:30	2026-06-29 11:03:58.91+05:30
a34456dc-fc25-4092-aae8-d3f8fd29d76f	681a88ab-5628-4081-af04-22aeb74daef2	Favela | ONYX	favela-onyx	Gastro Sky Bar | The Key Club	🪙₹ 3500 for two                        \r\n🎟️ 50% discounts for Lunara Users | Free Couple Entry\r\n🍽️ Continental, North Indian, Chinese, Pizza, Fast Food, Biryani, Desserts, Bar Food\r\n🍷 Full bar available\r\n📍922, Terrace, Suratwala Mark Plazzo, Near Indian Oil Petrol Pump, Hinjawadi, Pune	rooftop	["nightclub", "pub", "bar", "rooftop", "Dance floor"]	922, Terrace, Suratwala Mark Plazzo, Near Indian Oil Petrol Pump, Hinjawadi, Pune		Hinjewadi	Pune	Maharashtra	411057	India	18.59041100	73.74818300	0				8055754999	8208212661	favelapune1997@gmail.com		favelapune		Mr.Amit	Manager	8208212661						200	100	200	04:00:00	01:30:00	["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]	21	2000.00	2000.00	50.00	0.00	0.00	0.00	0.00	Smart Casual	["Indian", "Modern European", "Continental", "Asian Fusion", "Asian", "Chinese", "Italian", "Finger Food", "Pub Grub", "Goan", "Seafood", "Bombay Style", "Mediterranean", "Irish", "British"]	["EDM", "Deep House", "House", "Lounge", "Techno", "Chill", "Commercial", "Irish Folk", "Retro", "Bollywood", "Hip-Hop", "Jukebox", "Rock", "Pop", "Jazz", "Acoustic"]	{"hasAC": true, "hasDJ": true, "hasPool": false, "hasWifi": true, "hasParking": true, "hasRooftop": true, "hasLiveMusic": true, "hasDanceFloor": true, "hasHappyHours": true, "hasVIPSection": false, "hasSmokingZone": true, "hasValetParking": false, "hasBottleService": true, "hasPrivateDining": true, "hasOutdoorSeating": true}										0.00	0	live	2026-06-27 16:33:11.609+05:30	bc3d2498f90c41c21da5187b4c874969b8ebbf983fa48a0d52b820d5fb512805	2026-06-30 16:33:11.609+05:30	\N	\N	f	t	f	f	2026-06-27 16:33:11.58+05:30	2026-06-30 16:15:39.022+05:30
ab320228-2d2f-41da-9d07-c9f5a915211e	681a88ab-5628-4081-af04-22aeb74daef2	Sash	sash	Cocktail Bar & Kitchen	🪙₹ 1500 for two                        \r\n🎟️ 40% discounts for Lunara Users | Free Entry For All\r\n🍽️ North Indian, Continental, Kebab, Chinese, Seafood\r\n🍷 Full bar available\r\n📍1, Lunkad Sky Max, Clover Park, Datta Mandir Chowk, Viman Nagar, Pune	club	["nightclub", "bar", "club", "pub", "dancefloor"]	1, Lunkad Sky Max, Clover Park, Datta Mandir Chowk, Viman Nagar, Pune		Viman Nagar	Pune	Maharashtra	411014	India	18.56534900	73.91371100	0	Sky Max Mall	1, Lunkad Sky Max, Clover Park, Datta Mandir Chowk, Viman Nagar, Pune		70586 47114		Sashcocktailbarandkitchen@gmail.com				Mr.Ritesh		7058647114						120	80	120	12:00:00	12:00:00	["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]	21	\N	\N	40.00	10.00	0.00	0.00	0.00	Smart Casual	["Indian", "Modern European", "Continental", "Asian", "Asian Fusion", "Pub Grub", "Chinese", "Italian", "Finger Food", "Bombay Style", "Goan", "Seafood", "Mediterranean", "Irish", "British"]	["Acoustic", "Jazz", "Pop", "Hip-Hop", "Jukebox", "Retro", "Bollywood", "Rock", "Commercial", "Irish Folk", "Lounge", "Techno", "House", "EDM", "Deep House", "Chill"]	{"hasAC": true, "hasDJ": true, "hasPool": true, "hasWifi": true, "hasParking": true, "hasRooftop": false, "hasLiveMusic": true, "hasDanceFloor": true, "hasHappyHours": false, "hasVIPSection": false, "hasSmokingZone": true, "hasValetParking": false, "hasBottleService": true, "hasPrivateDining": false, "hasOutdoorSeating": false}										0.00	0	live	2026-07-03 00:13:15.027+05:30	467c4dd95198051d598b9e7c85f0bd05425997c3f3997fb6d34598a1cd2a9b8b	2026-07-06 00:13:15.027+05:30	\N	\N	f	t	f	f	2026-07-03 00:13:15.008+05:30	2026-07-04 18:46:15.812+05:30
14292123-33fc-4c0f-b583-c2e532fd6c2d	681a88ab-5628-4081-af04-22aeb74daef2	AURA BAR & KITCHEN 	aura-bar-kitchen		🪙₹ 3000 for two                        \r\n🎟️Free Couple Entry\r\n🍽️ Continental, North Indian, Chinese, Pizza, Fast Food, Biryani, Desserts, Bar Food\r\n🍷 Full bar available\r\n📍Hinjewadi - Wakad Rd, next to HP Petrol Pump, beside The Social Street, Hinjawadi Pune	bar	["nightclub", "pub", "bar", "dance floor"]	Hinjewadi - Wakad Rd, next to HP Petrol Pump, beside The Social Street, Hinjawadi, Pune		Hinjewadi	Pune	Maharashtra	411057	India	18.59025000	73.74595900	0	The Social Street	Beside The Social Street		78880 50777		Chefpradipkhatua55@gmail.com		aura.hinjewadi		Mr. Pradip		6399697955						200	150	200	12:00:00	12:00:00	["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]	21	600.00	600.00	0.00	0.00	0.00	0.00	0.00	Smart Casual	["Indian", "Modern European", "Continental", "Asian Fusion", "Asian", "Chinese", "Pub Grub", "Italian", "Finger Food", "Goan", "Bombay Style", "Seafood", "Mediterranean", "Irish", "British"]	["Acoustic", "Jazz", "Pop", "Rock", "Hip-Hop", "Jukebox", "Retro", "Bollywood", "Commercial", "Irish Folk", "Chill", "Techno", "Lounge", "House", "Deep House", "EDM"]	{"hasAC": true, "hasDJ": true, "hasPool": false, "hasWifi": true, "hasParking": true, "hasRooftop": false, "hasLiveMusic": true, "hasDanceFloor": true, "hasHappyHours": true, "hasVIPSection": true, "hasSmokingZone": true, "hasValetParking": false, "hasBottleService": true, "hasPrivateDining": true, "hasOutdoorSeating": false}										0.00	0	pending	2026-07-05 11:17:30.425+05:30	d158432f19dbfd9d72259f536f29a77fa782fafc19238d4b79d462b9b0526dc7	2026-07-08 11:17:30.425+05:30	\N	\N	f	t	f	f	2026-07-05 11:17:30.394+05:30	2026-07-05 11:17:51.623+05:30
\.


--
-- Name: SubscriptionPackages SubscriptionPackages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."SubscriptionPackages"
    ADD CONSTRAINT "SubscriptionPackages_pkey" PRIMARY KEY (id);


--
-- Name: UserSubscriptions UserSubscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserSubscriptions"
    ADD CONSTRAINT "UserSubscriptions_pkey" PRIMARY KEY (id);


--
-- Name: ads ads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ads
    ADD CONSTRAINT ads_pkey PRIMARY KEY (id);


--
-- Name: booking_members booking_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.booking_members
    ADD CONSTRAINT booking_members_pkey PRIMARY KEY (id);


--
-- Name: booking_table_packages booking_table_packages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.booking_table_packages
    ADD CONSTRAINT booking_table_packages_pkey PRIMARY KEY (id);


--
-- Name: bookings bookings_booking_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key1 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key10; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key10 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key11; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key11 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key12; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key12 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key13; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key13 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key14; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key14 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key15; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key15 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key16; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key16 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key17; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key17 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key18; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key18 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key19; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key19 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key2 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key20; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key20 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key21; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key21 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key22; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key22 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key23; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key23 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key24; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key24 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key25; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key25 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key26; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key26 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key27; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key27 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key28; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key28 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key29; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key29 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key3; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key3 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key30; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key30 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key31; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key31 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key32; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key32 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key33; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key33 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key34; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key34 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key35; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key35 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key4 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key5 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key6 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key7; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key7 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key8; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key8 UNIQUE (booking_number);


--
-- Name: bookings bookings_booking_number_key9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booking_number_key9 UNIQUE (booking_number);


--
-- Name: bookings bookings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_pkey PRIMARY KEY (id);


--
-- Name: bookings bookings_ticket_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key1 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key10; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key10 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key11; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key11 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key12; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key12 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key13; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key13 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key14; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key14 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key15; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key15 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key16; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key16 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key17; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key17 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key18; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key18 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key19; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key19 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key2 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key20; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key20 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key21; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key21 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key22; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key22 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key23; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key23 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key24; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key24 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key25; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key25 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key26; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key26 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key27; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key27 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key28; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key28 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key29; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key29 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key3; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key3 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key30; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key30 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key31; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key31 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key32; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key32 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key33; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key33 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key34; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key34 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key35; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key35 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key4 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key5 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key6 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key7; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key7 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key8; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key8 UNIQUE (ticket_code);


--
-- Name: bookings bookings_ticket_code_key9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ticket_code_key9 UNIQUE (ticket_code);


--
-- Name: chat_subscriptions chat_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_subscriptions
    ADD CONSTRAINT chat_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: cities cities_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key UNIQUE (name);


--
-- Name: cities cities_name_key1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key1 UNIQUE (name);


--
-- Name: cities cities_name_key10; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key10 UNIQUE (name);


--
-- Name: cities cities_name_key11; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key11 UNIQUE (name);


--
-- Name: cities cities_name_key12; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key12 UNIQUE (name);


--
-- Name: cities cities_name_key13; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key13 UNIQUE (name);


--
-- Name: cities cities_name_key14; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key14 UNIQUE (name);


--
-- Name: cities cities_name_key15; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key15 UNIQUE (name);


--
-- Name: cities cities_name_key16; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key16 UNIQUE (name);


--
-- Name: cities cities_name_key17; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key17 UNIQUE (name);


--
-- Name: cities cities_name_key18; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key18 UNIQUE (name);


--
-- Name: cities cities_name_key19; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key19 UNIQUE (name);


--
-- Name: cities cities_name_key2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key2 UNIQUE (name);


--
-- Name: cities cities_name_key20; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key20 UNIQUE (name);


--
-- Name: cities cities_name_key21; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key21 UNIQUE (name);


--
-- Name: cities cities_name_key22; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key22 UNIQUE (name);


--
-- Name: cities cities_name_key23; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key23 UNIQUE (name);


--
-- Name: cities cities_name_key24; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key24 UNIQUE (name);


--
-- Name: cities cities_name_key25; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key25 UNIQUE (name);


--
-- Name: cities cities_name_key26; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key26 UNIQUE (name);


--
-- Name: cities cities_name_key27; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key27 UNIQUE (name);


--
-- Name: cities cities_name_key28; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key28 UNIQUE (name);


--
-- Name: cities cities_name_key29; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key29 UNIQUE (name);


--
-- Name: cities cities_name_key3; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key3 UNIQUE (name);


--
-- Name: cities cities_name_key30; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key30 UNIQUE (name);


--
-- Name: cities cities_name_key4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key4 UNIQUE (name);


--
-- Name: cities cities_name_key5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key5 UNIQUE (name);


--
-- Name: cities cities_name_key6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key6 UNIQUE (name);


--
-- Name: cities cities_name_key7; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key7 UNIQUE (name);


--
-- Name: cities cities_name_key8; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key8 UNIQUE (name);


--
-- Name: cities cities_name_key9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_name_key9 UNIQUE (name);


--
-- Name: cities cities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_pkey PRIMARY KEY (id);


--
-- Name: community_guidelines community_guidelines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.community_guidelines
    ADD CONSTRAINT community_guidelines_pkey PRIMARY KEY (id);


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


--
-- Name: email_verifications email_verifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_pkey PRIMARY KEY (id);


--
-- Name: email_verifications email_verifications_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key1 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key10; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key10 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key11; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key11 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key12; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key12 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key13; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key13 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key14; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key14 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key15; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key15 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key16; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key16 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key17; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key17 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key18; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key18 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key19; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key19 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key2 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key20; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key20 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key21; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key21 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key22; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key22 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key23; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key23 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key24; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key24 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key25; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key25 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key26; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key26 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key27; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key27 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key28; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key28 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key29; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key29 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key3; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key3 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key30; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key30 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key31; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key31 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key32; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key32 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key33; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key33 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key34; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key34 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key4 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key5 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key6 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key7; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key7 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key8; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key8 UNIQUE (token);


--
-- Name: email_verifications email_verifications_token_key9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_token_key9 UNIQUE (token);


--
-- Name: group_bookings group_bookings_invitation_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key1 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key10; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key10 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key11; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key11 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key12; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key12 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key13; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key13 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key14; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key14 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key15; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key15 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key16; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key16 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key17; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key17 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key18; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key18 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key19; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key19 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key2 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key20; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key20 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key21; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key21 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key22; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key22 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key23; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key23 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key24; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key24 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key25; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key25 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key26; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key26 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key27; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key27 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key28; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key28 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key29; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key29 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key3; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key3 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key30; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key30 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key31; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key31 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key32; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key32 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key33; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key33 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key34; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key34 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key35; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key35 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key4 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key5 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key6 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key7; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key7 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key8; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key8 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_invitation_code_key9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_invitation_code_key9 UNIQUE (invitation_code);


--
-- Name: group_bookings group_bookings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_pkey PRIMARY KEY (id);


--
-- Name: group_parties group_parties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_parties
    ADD CONSTRAINT group_parties_pkey PRIMARY KEY (id);


--
-- Name: help_articles help_articles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.help_articles
    ADD CONSTRAINT help_articles_pkey PRIMARY KEY (id);


--
-- Name: legal_documents legal_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legal_documents
    ADD CONSTRAINT legal_documents_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: otp_verifications otp_verifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.otp_verifications
    ADD CONSTRAINT otp_verifications_pkey PRIMARY KEY (id);


--
-- Name: party_plan_requests party_plan_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_plan_requests
    ADD CONSTRAINT party_plan_requests_pkey PRIMARY KEY (id);


--
-- Name: party_plans party_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_plans
    ADD CONSTRAINT party_plans_pkey PRIMARY KEY (id);


--
-- Name: password_reset_tokens password_reset_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_pkey PRIMARY KEY (id);


--
-- Name: password_reset_tokens password_reset_tokens_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key1 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key10; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key10 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key11; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key11 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key12; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key12 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key13; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key13 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key14; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key14 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key15; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key15 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key16; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key16 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key17; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key17 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key18; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key18 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key19; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key19 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key2 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key20; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key20 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key21; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key21 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key22; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key22 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key23; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key23 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key24; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key24 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key25; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key25 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key26; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key26 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key27; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key27 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key28; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key28 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key29; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key29 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key3; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key3 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key30; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key30 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key31; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key31 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key32; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key32 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key33; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key33 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key34; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key34 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key4 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key5 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key6 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key7; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key7 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key8; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key8 UNIQUE (token);


--
-- Name: password_reset_tokens password_reset_tokens_token_key9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_key9 UNIQUE (token);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: payments payments_transaction_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key1 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key10; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key10 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key11; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key11 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key12; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key12 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key13; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key13 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key14; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key14 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key15; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key15 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key16; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key16 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key17; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key17 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key18; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key18 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key19; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key19 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key2 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key20; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key20 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key21; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key21 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key22; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key22 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key23; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key23 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key24; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key24 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key25; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key25 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key26; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key26 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key27; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key27 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key28; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key28 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key29; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key29 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key3; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key3 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key30; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key30 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key31; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key31 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key32; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key32 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key33; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key33 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key34; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key34 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key35; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key35 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key4 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key5 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key6 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key7; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key7 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key8; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key8 UNIQUE (transaction_id);


--
-- Name: payments payments_transaction_id_key9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_transaction_id_key9 UNIQUE (transaction_id);


--
-- Name: plan_join_requests plan_join_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_join_requests
    ADD CONSTRAINT plan_join_requests_pkey PRIMARY KEY (id);


--
-- Name: plans plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT plans_pkey PRIMARY KEY (id);


--
-- Name: social_connections social_connections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.social_connections
    ADD CONSTRAINT social_connections_pkey PRIMARY KEY (id);


--
-- Name: strangers_meet_joiners strangers_meet_joiners_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_joiners
    ADD CONSTRAINT strangers_meet_joiners_pkey PRIMARY KEY (id);


--
-- Name: strangers_meet_requests strangers_meet_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_pkey PRIMARY KEY (id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key1 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key10; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key10 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key11; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key11 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key12; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key12 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key13; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key13 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key14; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key14 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key15; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key15 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key16; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key16 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key17; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key17 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key18; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key18 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key19; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key19 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key2 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key20; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key20 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key21; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key21 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key22; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key22 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key23; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key23 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key24; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key24 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key25; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key25 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key26; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key26 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key27; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key27 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key28; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key28 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key29; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key29 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key3; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key3 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key30; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key30 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key31; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key31 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key4 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key5 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key6 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key7; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key7 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key8; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key8 UNIQUE (ticket_id);


--
-- Name: strangers_meet_requests strangers_meet_requests_ticket_id_key9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_ticket_id_key9 UNIQUE (ticket_id);


--
-- Name: user_interests user_interests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_interests
    ADD CONSTRAINT user_interests_pkey PRIMARY KEY (id);


--
-- Name: user_matches user_matches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_matches
    ADD CONSTRAINT user_matches_pkey PRIMARY KEY (id);


--
-- Name: user_penalties user_penalties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_penalties
    ADD CONSTRAINT user_penalties_pkey PRIMARY KEY (id);


--
-- Name: user_photos user_photos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_photos
    ADD CONSTRAINT user_photos_pkey PRIMARY KEY (id);


--
-- Name: user_preferences user_preferences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_preferences
    ADD CONSTRAINT user_preferences_pkey PRIMARY KEY (id);


--
-- Name: user_preferences user_preferences_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_preferences
    ADD CONSTRAINT user_preferences_user_id_key UNIQUE (user_id);


--
-- Name: user_profiles user_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_pkey PRIMARY KEY (id);


--
-- Name: user_profiles user_profiles_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_user_id_key UNIQUE (user_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_email_key1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key1 UNIQUE (email);


--
-- Name: users users_email_key10; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key10 UNIQUE (email);


--
-- Name: users users_email_key11; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key11 UNIQUE (email);


--
-- Name: users users_email_key12; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key12 UNIQUE (email);


--
-- Name: users users_email_key13; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key13 UNIQUE (email);


--
-- Name: users users_email_key14; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key14 UNIQUE (email);


--
-- Name: users users_email_key15; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key15 UNIQUE (email);


--
-- Name: users users_email_key16; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key16 UNIQUE (email);


--
-- Name: users users_email_key17; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key17 UNIQUE (email);


--
-- Name: users users_email_key18; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key18 UNIQUE (email);


--
-- Name: users users_email_key19; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key19 UNIQUE (email);


--
-- Name: users users_email_key2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key2 UNIQUE (email);


--
-- Name: users users_email_key20; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key20 UNIQUE (email);


--
-- Name: users users_email_key21; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key21 UNIQUE (email);


--
-- Name: users users_email_key22; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key22 UNIQUE (email);


--
-- Name: users users_email_key23; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key23 UNIQUE (email);


--
-- Name: users users_email_key24; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key24 UNIQUE (email);


--
-- Name: users users_email_key25; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key25 UNIQUE (email);


--
-- Name: users users_email_key26; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key26 UNIQUE (email);


--
-- Name: users users_email_key27; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key27 UNIQUE (email);


--
-- Name: users users_email_key28; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key28 UNIQUE (email);


--
-- Name: users users_email_key29; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key29 UNIQUE (email);


--
-- Name: users users_email_key3; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key3 UNIQUE (email);


--
-- Name: users users_email_key30; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key30 UNIQUE (email);


--
-- Name: users users_email_key31; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key31 UNIQUE (email);


--
-- Name: users users_email_key32; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key32 UNIQUE (email);


--
-- Name: users users_email_key33; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key33 UNIQUE (email);


--
-- Name: users users_email_key34; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key34 UNIQUE (email);


--
-- Name: users users_email_key35; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key35 UNIQUE (email);


--
-- Name: users users_email_key36; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key36 UNIQUE (email);


--
-- Name: users users_email_key37; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key37 UNIQUE (email);


--
-- Name: users users_email_key38; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key38 UNIQUE (email);


--
-- Name: users users_email_key39; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key39 UNIQUE (email);


--
-- Name: users users_email_key4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key4 UNIQUE (email);


--
-- Name: users users_email_key40; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key40 UNIQUE (email);


--
-- Name: users users_email_key41; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key41 UNIQUE (email);


--
-- Name: users users_email_key42; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key42 UNIQUE (email);


--
-- Name: users users_email_key43; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key43 UNIQUE (email);


--
-- Name: users users_email_key44; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key44 UNIQUE (email);


--
-- Name: users users_email_key45; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key45 UNIQUE (email);


--
-- Name: users users_email_key46; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key46 UNIQUE (email);


--
-- Name: users users_email_key47; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key47 UNIQUE (email);


--
-- Name: users users_email_key48; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key48 UNIQUE (email);


--
-- Name: users users_email_key5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key5 UNIQUE (email);


--
-- Name: users users_email_key6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key6 UNIQUE (email);


--
-- Name: users users_email_key7; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key7 UNIQUE (email);


--
-- Name: users users_email_key8; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key8 UNIQUE (email);


--
-- Name: users users_email_key9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key9 UNIQUE (email);


--
-- Name: users users_phone_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key UNIQUE (phone);


--
-- Name: users users_phone_key1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key1 UNIQUE (phone);


--
-- Name: users users_phone_key10; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key10 UNIQUE (phone);


--
-- Name: users users_phone_key11; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key11 UNIQUE (phone);


--
-- Name: users users_phone_key12; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key12 UNIQUE (phone);


--
-- Name: users users_phone_key13; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key13 UNIQUE (phone);


--
-- Name: users users_phone_key14; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key14 UNIQUE (phone);


--
-- Name: users users_phone_key15; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key15 UNIQUE (phone);


--
-- Name: users users_phone_key16; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key16 UNIQUE (phone);


--
-- Name: users users_phone_key17; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key17 UNIQUE (phone);


--
-- Name: users users_phone_key18; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key18 UNIQUE (phone);


--
-- Name: users users_phone_key19; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key19 UNIQUE (phone);


--
-- Name: users users_phone_key2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key2 UNIQUE (phone);


--
-- Name: users users_phone_key20; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key20 UNIQUE (phone);


--
-- Name: users users_phone_key21; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key21 UNIQUE (phone);


--
-- Name: users users_phone_key22; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key22 UNIQUE (phone);


--
-- Name: users users_phone_key23; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key23 UNIQUE (phone);


--
-- Name: users users_phone_key24; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key24 UNIQUE (phone);


--
-- Name: users users_phone_key25; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key25 UNIQUE (phone);


--
-- Name: users users_phone_key26; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key26 UNIQUE (phone);


--
-- Name: users users_phone_key27; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key27 UNIQUE (phone);


--
-- Name: users users_phone_key28; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key28 UNIQUE (phone);


--
-- Name: users users_phone_key29; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key29 UNIQUE (phone);


--
-- Name: users users_phone_key3; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key3 UNIQUE (phone);


--
-- Name: users users_phone_key30; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key30 UNIQUE (phone);


--
-- Name: users users_phone_key31; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key31 UNIQUE (phone);


--
-- Name: users users_phone_key32; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key32 UNIQUE (phone);


--
-- Name: users users_phone_key33; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key33 UNIQUE (phone);


--
-- Name: users users_phone_key34; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key34 UNIQUE (phone);


--
-- Name: users users_phone_key35; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key35 UNIQUE (phone);


--
-- Name: users users_phone_key36; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key36 UNIQUE (phone);


--
-- Name: users users_phone_key37; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key37 UNIQUE (phone);


--
-- Name: users users_phone_key38; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key38 UNIQUE (phone);


--
-- Name: users users_phone_key39; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key39 UNIQUE (phone);


--
-- Name: users users_phone_key4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key4 UNIQUE (phone);


--
-- Name: users users_phone_key40; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key40 UNIQUE (phone);


--
-- Name: users users_phone_key41; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key41 UNIQUE (phone);


--
-- Name: users users_phone_key42; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key42 UNIQUE (phone);


--
-- Name: users users_phone_key43; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key43 UNIQUE (phone);


--
-- Name: users users_phone_key44; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key44 UNIQUE (phone);


--
-- Name: users users_phone_key45; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key45 UNIQUE (phone);


--
-- Name: users users_phone_key46; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key46 UNIQUE (phone);


--
-- Name: users users_phone_key47; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key47 UNIQUE (phone);


--
-- Name: users users_phone_key48; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key48 UNIQUE (phone);


--
-- Name: users users_phone_key5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key5 UNIQUE (phone);


--
-- Name: users users_phone_key6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key6 UNIQUE (phone);


--
-- Name: users users_phone_key7; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key7 UNIQUE (phone);


--
-- Name: users users_phone_key8; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key8 UNIQUE (phone);


--
-- Name: users users_phone_key9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key9 UNIQUE (phone);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: venue_compliance_logs venue_compliance_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venue_compliance_logs
    ADD CONSTRAINT venue_compliance_logs_pkey PRIMARY KEY (id);


--
-- Name: venue_images venue_images_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venue_images
    ADD CONSTRAINT venue_images_pkey PRIMARY KEY (id);


--
-- Name: venues venues_confirmation_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key1 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key10; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key10 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key11; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key11 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key12; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key12 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key13; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key13 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key14; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key14 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key15; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key15 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key16; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key16 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key17; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key17 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key18; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key18 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key19; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key19 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key2 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key20; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key20 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key21; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key21 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key22; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key22 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key23; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key23 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key24; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key24 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key25; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key25 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key26; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key26 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key27; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key27 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key28; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key28 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key29; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key29 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key3; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key3 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key30; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key30 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key31; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key31 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key32; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key32 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key33; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key33 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key34; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key34 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key35; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key35 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key36; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key36 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key37; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key37 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key38; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key38 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key39; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key39 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key4 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key40; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key40 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key41; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key41 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key42; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key42 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key43; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key43 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key44; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key44 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key45; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key45 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key46; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key46 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key5 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key6 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key7; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key7 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key8; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key8 UNIQUE (confirmation_token);


--
-- Name: venues venues_confirmation_token_key9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_confirmation_token_key9 UNIQUE (confirmation_token);


--
-- Name: venues venues_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_pkey PRIMARY KEY (id);


--
-- Name: venues venues_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key UNIQUE (slug);


--
-- Name: venues venues_slug_key1; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key1 UNIQUE (slug);


--
-- Name: venues venues_slug_key10; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key10 UNIQUE (slug);


--
-- Name: venues venues_slug_key11; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key11 UNIQUE (slug);


--
-- Name: venues venues_slug_key12; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key12 UNIQUE (slug);


--
-- Name: venues venues_slug_key13; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key13 UNIQUE (slug);


--
-- Name: venues venues_slug_key14; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key14 UNIQUE (slug);


--
-- Name: venues venues_slug_key15; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key15 UNIQUE (slug);


--
-- Name: venues venues_slug_key16; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key16 UNIQUE (slug);


--
-- Name: venues venues_slug_key17; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key17 UNIQUE (slug);


--
-- Name: venues venues_slug_key18; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key18 UNIQUE (slug);


--
-- Name: venues venues_slug_key19; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key19 UNIQUE (slug);


--
-- Name: venues venues_slug_key2; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key2 UNIQUE (slug);


--
-- Name: venues venues_slug_key20; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key20 UNIQUE (slug);


--
-- Name: venues venues_slug_key21; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key21 UNIQUE (slug);


--
-- Name: venues venues_slug_key22; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key22 UNIQUE (slug);


--
-- Name: venues venues_slug_key23; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key23 UNIQUE (slug);


--
-- Name: venues venues_slug_key24; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key24 UNIQUE (slug);


--
-- Name: venues venues_slug_key25; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key25 UNIQUE (slug);


--
-- Name: venues venues_slug_key26; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key26 UNIQUE (slug);


--
-- Name: venues venues_slug_key27; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key27 UNIQUE (slug);


--
-- Name: venues venues_slug_key28; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key28 UNIQUE (slug);


--
-- Name: venues venues_slug_key29; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key29 UNIQUE (slug);


--
-- Name: venues venues_slug_key3; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key3 UNIQUE (slug);


--
-- Name: venues venues_slug_key30; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key30 UNIQUE (slug);


--
-- Name: venues venues_slug_key31; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key31 UNIQUE (slug);


--
-- Name: venues venues_slug_key32; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key32 UNIQUE (slug);


--
-- Name: venues venues_slug_key33; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key33 UNIQUE (slug);


--
-- Name: venues venues_slug_key34; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key34 UNIQUE (slug);


--
-- Name: venues venues_slug_key35; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key35 UNIQUE (slug);


--
-- Name: venues venues_slug_key36; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key36 UNIQUE (slug);


--
-- Name: venues venues_slug_key37; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key37 UNIQUE (slug);


--
-- Name: venues venues_slug_key38; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key38 UNIQUE (slug);


--
-- Name: venues venues_slug_key39; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key39 UNIQUE (slug);


--
-- Name: venues venues_slug_key4; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key4 UNIQUE (slug);


--
-- Name: venues venues_slug_key40; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key40 UNIQUE (slug);


--
-- Name: venues venues_slug_key41; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key41 UNIQUE (slug);


--
-- Name: venues venues_slug_key42; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key42 UNIQUE (slug);


--
-- Name: venues venues_slug_key43; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key43 UNIQUE (slug);


--
-- Name: venues venues_slug_key44; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key44 UNIQUE (slug);


--
-- Name: venues venues_slug_key45; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key45 UNIQUE (slug);


--
-- Name: venues venues_slug_key46; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key46 UNIQUE (slug);


--
-- Name: venues venues_slug_key5; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key5 UNIQUE (slug);


--
-- Name: venues venues_slug_key6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key6 UNIQUE (slug);


--
-- Name: venues venues_slug_key7; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key7 UNIQUE (slug);


--
-- Name: venues venues_slug_key8; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key8 UNIQUE (slug);


--
-- Name: venues venues_slug_key9; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_slug_key9 UNIQUE (slug);


--
-- Name: ads_city_area_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ads_city_area_type ON public.ads USING btree (city, area, type);


--
-- Name: ads_is_active_from_date_to_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ads_is_active_from_date_to_date ON public.ads USING btree (is_active, from_date, to_date);


--
-- Name: ads_venue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ads_venue_id ON public.ads USING btree (venue_id);


--
-- Name: booking_members_group_booking_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX booking_members_group_booking_id ON public.booking_members USING btree (group_booking_id);


--
-- Name: booking_members_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX booking_members_user_id ON public.booking_members USING btree (user_id);


--
-- Name: booking_table_packages_venue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX booking_table_packages_venue_id ON public.booking_table_packages USING btree (venue_id);


--
-- Name: booking_table_packages_venue_id_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX booking_table_packages_venue_id_name ON public.booking_table_packages USING btree (venue_id, name);


--
-- Name: bookings_booking_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bookings_booking_date ON public.bookings USING btree (booking_date);


--
-- Name: bookings_booking_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX bookings_booking_number ON public.bookings USING btree (booking_number);


--
-- Name: bookings_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bookings_status ON public.bookings USING btree (status);


--
-- Name: bookings_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bookings_user_id ON public.bookings USING btree (user_id);


--
-- Name: bookings_venue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bookings_venue_id ON public.bookings USING btree (venue_id);


--
-- Name: chat_subscriptions_conversation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chat_subscriptions_conversation_id ON public.chat_subscriptions USING btree (conversation_id);


--
-- Name: chat_subscriptions_paid_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chat_subscriptions_paid_by_id ON public.chat_subscriptions USING btree (paid_by_id);


--
-- Name: chat_subscriptions_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chat_subscriptions_status ON public.chat_subscriptions USING btree (status);


--
-- Name: chat_subscriptions_valid_until; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chat_subscriptions_valid_until ON public.chat_subscriptions USING btree (valid_until);


--
-- Name: cities_display_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cities_display_order ON public.cities USING btree (display_order);


--
-- Name: cities_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cities_is_active ON public.cities USING btree (is_active);


--
-- Name: cities_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX cities_name ON public.cities USING btree (name);


--
-- Name: community_guidelines_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX community_guidelines_category ON public.community_guidelines USING btree (category);


--
-- Name: community_guidelines_display_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX community_guidelines_display_order ON public.community_guidelines USING btree (display_order);


--
-- Name: community_guidelines_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX community_guidelines_is_active ON public.community_guidelines USING btree (is_active);


--
-- Name: conversations_last_message_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX conversations_last_message_at ON public.conversations USING btree (last_message_at);


--
-- Name: conversations_participant_one; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX conversations_participant_one ON public.conversations USING btree (participant_one);


--
-- Name: conversations_participant_one_participant_two; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX conversations_participant_one_participant_two ON public.conversations USING btree (participant_one, participant_two);


--
-- Name: conversations_participant_two; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX conversations_participant_two ON public.conversations USING btree (participant_two);


--
-- Name: email_verifications_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX email_verifications_token ON public.email_verifications USING btree (token);


--
-- Name: email_verifications_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX email_verifications_user_id ON public.email_verifications USING btree (user_id);


--
-- Name: group_bookings_booking_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX group_bookings_booking_id ON public.group_bookings USING btree (booking_id);


--
-- Name: group_bookings_invitation_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX group_bookings_invitation_code ON public.group_bookings USING btree (invitation_code);


--
-- Name: group_bookings_organizer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX group_bookings_organizer_id ON public.group_bookings USING btree (organizer_id);


--
-- Name: group_parties_party_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX group_parties_party_date ON public.group_parties USING btree (party_date);


--
-- Name: group_parties_payment_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX group_parties_payment_status ON public.group_parties USING btree (payment_status);


--
-- Name: group_parties_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX group_parties_status ON public.group_parties USING btree (status);


--
-- Name: group_parties_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX group_parties_user_id ON public.group_parties USING btree (user_id);


--
-- Name: group_parties_venue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX group_parties_venue_id ON public.group_parties USING btree (venue_id);


--
-- Name: help_articles_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX help_articles_category ON public.help_articles USING btree (category);


--
-- Name: help_articles_display_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX help_articles_display_order ON public.help_articles USING btree (display_order);


--
-- Name: help_articles_is_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX help_articles_is_published ON public.help_articles USING btree (is_published);


--
-- Name: legal_documents_effective_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX legal_documents_effective_date ON public.legal_documents USING btree (effective_date);


--
-- Name: legal_documents_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX legal_documents_is_active ON public.legal_documents USING btree (is_active);


--
-- Name: legal_documents_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX legal_documents_type ON public.legal_documents USING btree (type);


--
-- Name: messages_conversation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_conversation_id ON public.messages USING btree (conversation_id);


--
-- Name: messages_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_created_at ON public.messages USING btree (created_at);


--
-- Name: messages_sender_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_sender_id ON public.messages USING btree (sender_id);


--
-- Name: messages_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_type ON public.messages USING btree (type);


--
-- Name: otp_verifications_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX otp_verifications_expires_at ON public.otp_verifications USING btree (expires_at);


--
-- Name: otp_verifications_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX otp_verifications_phone ON public.otp_verifications USING btree (phone);


--
-- Name: otp_verifications_phone_purpose; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX otp_verifications_phone_purpose ON public.otp_verifications USING btree (phone, purpose);


--
-- Name: party_plan_requests_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX party_plan_requests_plan_id ON public.party_plan_requests USING btree (plan_id);


--
-- Name: party_plan_requests_requester_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX party_plan_requests_requester_id ON public.party_plan_requests USING btree (requester_id);


--
-- Name: party_plan_requests_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX party_plan_requests_status ON public.party_plan_requests USING btree (status);


--
-- Name: party_plans_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX party_plans_created_at ON public.party_plans USING btree (created_at);


--
-- Name: party_plans_plan_date_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX party_plans_plan_date_time ON public.party_plans USING btree (plan_date_time);


--
-- Name: party_plans_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX party_plans_status ON public.party_plans USING btree (status);


--
-- Name: party_plans_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX party_plans_user_id ON public.party_plans USING btree (user_id);


--
-- Name: party_plans_venue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX party_plans_venue_id ON public.party_plans USING btree (venue_id);


--
-- Name: password_reset_tokens_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX password_reset_tokens_expires_at ON public.password_reset_tokens USING btree (expires_at);


--
-- Name: password_reset_tokens_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX password_reset_tokens_token ON public.password_reset_tokens USING btree (token);


--
-- Name: password_reset_tokens_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX password_reset_tokens_user_id ON public.password_reset_tokens USING btree (user_id);


--
-- Name: payments_booking_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payments_booking_id ON public.payments USING btree (booking_id);


--
-- Name: payments_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payments_status ON public.payments USING btree (status);


--
-- Name: payments_transaction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX payments_transaction_id ON public.payments USING btree (transaction_id);


--
-- Name: payments_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payments_user_id ON public.payments USING btree (user_id);


--
-- Name: plan_join_requests_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX plan_join_requests_plan_id ON public.plan_join_requests USING btree (plan_id);


--
-- Name: plan_join_requests_requester_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX plan_join_requests_requester_id ON public.plan_join_requests USING btree (requester_id);


--
-- Name: plan_join_requests_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX plan_join_requests_status ON public.plan_join_requests USING btree (status);


--
-- Name: plans_plan_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX plans_plan_date ON public.plans USING btree (plan_date);


--
-- Name: plans_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX plans_status ON public.plans USING btree (status);


--
-- Name: plans_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX plans_user_id ON public.plans USING btree (user_id);


--
-- Name: plans_venue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX plans_venue_id ON public.plans USING btree (venue_id);


--
-- Name: social_connections_receiver_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX social_connections_receiver_id ON public.social_connections USING btree (receiver_id);


--
-- Name: social_connections_requester_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX social_connections_requester_id ON public.social_connections USING btree (requester_id);


--
-- Name: social_connections_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX social_connections_status ON public.social_connections USING btree (status);


--
-- Name: strangers_meet_joiners_payment_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX strangers_meet_joiners_payment_status ON public.strangers_meet_joiners USING btree (payment_status);


--
-- Name: strangers_meet_joiners_strangers_meet_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX strangers_meet_joiners_strangers_meet_request_id ON public.strangers_meet_joiners USING btree (strangers_meet_request_id);


--
-- Name: strangers_meet_joiners_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX strangers_meet_joiners_user_id ON public.strangers_meet_joiners USING btree (user_id);


--
-- Name: strangers_meet_requests_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX strangers_meet_requests_created_at ON public.strangers_meet_requests USING btree (created_at);


--
-- Name: strangers_meet_requests_payment_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX strangers_meet_requests_payment_status ON public.strangers_meet_requests USING btree (payment_status);


--
-- Name: strangers_meet_requests_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX strangers_meet_requests_status ON public.strangers_meet_requests USING btree (status);


--
-- Name: strangers_meet_requests_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX strangers_meet_requests_user_id ON public.strangers_meet_requests USING btree (user_id);


--
-- Name: strangers_meet_requests_venue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX strangers_meet_requests_venue_id ON public.strangers_meet_requests USING btree (venue_id);


--
-- Name: user_interests_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_interests_category ON public.user_interests USING btree (category);


--
-- Name: user_interests_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_interests_user_id ON public.user_interests USING btree (user_id);


--
-- Name: user_interests_user_id_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_interests_user_id_category ON public.user_interests USING btree (user_id, category);


--
-- Name: user_matches_compatibility_score; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_matches_compatibility_score ON public.user_matches USING btree (compatibility_score);


--
-- Name: user_matches_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_matches_expires_at ON public.user_matches USING btree (expires_at);


--
-- Name: user_matches_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_matches_status ON public.user_matches USING btree (status);


--
-- Name: user_matches_user1_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_matches_user1_id ON public.user_matches USING btree (user1_id);


--
-- Name: user_matches_user2_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_matches_user2_id ON public.user_matches USING btree (user2_id);


--
-- Name: user_penalties_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_penalties_user_id ON public.user_penalties USING btree (user_id);


--
-- Name: user_photos_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_photos_user_id ON public.user_photos USING btree (user_id);


--
-- Name: user_photos_user_id_is_primary; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_photos_user_id_is_primary ON public.user_photos USING btree (user_id, is_primary);


--
-- Name: user_preferences_show_me_in_matching; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_preferences_show_me_in_matching ON public.user_preferences USING btree (show_me_in_matching);


--
-- Name: user_preferences_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_preferences_user_id ON public.user_preferences USING btree (user_id);


--
-- Name: user_profiles_city; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_profiles_city ON public.user_profiles USING btree (city);


--
-- Name: user_profiles_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_profiles_user_id ON public.user_profiles USING btree (user_id);


--
-- Name: users_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_email ON public.users USING btree (email);


--
-- Name: users_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_phone ON public.users USING btree (phone);


--
-- Name: users_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_role ON public.users USING btree (role);


--
-- Name: venue_compliance_logs_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX venue_compliance_logs_event_type ON public.venue_compliance_logs USING btree (event_type);


--
-- Name: venue_compliance_logs_venue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX venue_compliance_logs_venue_id ON public.venue_compliance_logs USING btree (venue_id);


--
-- Name: venue_compliance_logs_venue_id_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX venue_compliance_logs_venue_id_event_type ON public.venue_compliance_logs USING btree (venue_id, event_type);


--
-- Name: venue_images_image_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX venue_images_image_type ON public.venue_images USING btree (image_type);


--
-- Name: venue_images_venue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX venue_images_venue_id ON public.venue_images USING btree (venue_id);


--
-- Name: venue_images_venue_id_is_primary; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX venue_images_venue_id_is_primary ON public.venue_images USING btree (venue_id, is_primary);


--
-- Name: venues_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX venues_category ON public.venues USING btree (category);


--
-- Name: venues_city; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX venues_city ON public.venues USING btree (city);


--
-- Name: venues_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX venues_owner_id ON public.venues USING btree (owner_id);


--
-- Name: venues_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX venues_slug ON public.venues USING btree (slug);


--
-- Name: venues_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX venues_status ON public.venues USING btree (status);


--
-- Name: UserSubscriptions UserSubscriptions_package_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserSubscriptions"
    ADD CONSTRAINT "UserSubscriptions_package_id_fkey" FOREIGN KEY (package_id) REFERENCES public."SubscriptionPackages"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: UserSubscriptions UserSubscriptions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."UserSubscriptions"
    ADD CONSTRAINT "UserSubscriptions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: ads ads_venue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ads
    ADD CONSTRAINT ads_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES public.venues(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: booking_members booking_members_group_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.booking_members
    ADD CONSTRAINT booking_members_group_booking_id_fkey FOREIGN KEY (group_booking_id) REFERENCES public.group_bookings(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: booking_table_packages booking_table_packages_venue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.booking_table_packages
    ADD CONSTRAINT booking_table_packages_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES public.venues(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: bookings bookings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: bookings bookings_venue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES public.venues(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: chat_subscriptions chat_subscriptions_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_subscriptions
    ADD CONSTRAINT chat_subscriptions_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: chat_subscriptions chat_subscriptions_paid_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_subscriptions
    ADD CONSTRAINT chat_subscriptions_paid_by_id_fkey FOREIGN KEY (paid_by_id) REFERENCES public.users(id) ON UPDATE CASCADE;


--
-- Name: chat_subscriptions chat_subscriptions_requested_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_subscriptions
    ADD CONSTRAINT chat_subscriptions_requested_by_id_fkey FOREIGN KEY (requested_by_id) REFERENCES public.users(id);


--
-- Name: conversations conversations_participant_one_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_participant_one_fkey FOREIGN KEY (participant_one) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: conversations conversations_participant_two_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_participant_two_fkey FOREIGN KEY (participant_two) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: email_verifications email_verifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_verifications
    ADD CONSTRAINT email_verifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: group_bookings group_bookings_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: group_bookings group_bookings_organizer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_bookings
    ADD CONSTRAINT group_bookings_organizer_id_fkey FOREIGN KEY (organizer_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: group_parties group_parties_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_parties
    ADD CONSTRAINT group_parties_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: group_parties group_parties_venue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_parties
    ADD CONSTRAINT group_parties_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES public.venues(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: messages messages_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: messages messages_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.users(id) ON UPDATE CASCADE;


--
-- Name: party_plan_requests party_plan_requests_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_plan_requests
    ADD CONSTRAINT party_plan_requests_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.party_plans(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: party_plan_requests party_plan_requests_requester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_plan_requests
    ADD CONSTRAINT party_plan_requests_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: party_plans party_plans_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_plans
    ADD CONSTRAINT party_plans_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: party_plans party_plans_venue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_plans
    ADD CONSTRAINT party_plans_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES public.venues(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: password_reset_tokens password_reset_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: payments payments_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: payments payments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: plan_join_requests plan_join_requests_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_join_requests
    ADD CONSTRAINT plan_join_requests_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.plans(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: plan_join_requests plan_join_requests_requester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_join_requests
    ADD CONSTRAINT plan_join_requests_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES public.users(id) ON UPDATE CASCADE;


--
-- Name: plans plans_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT plans_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: plans plans_venue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT plans_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES public.venues(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: social_connections social_connections_receiver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.social_connections
    ADD CONSTRAINT social_connections_receiver_id_fkey FOREIGN KEY (receiver_id) REFERENCES public.users(id) ON UPDATE CASCADE;


--
-- Name: social_connections social_connections_requester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.social_connections
    ADD CONSTRAINT social_connections_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES public.users(id) ON UPDATE CASCADE;


--
-- Name: strangers_meet_joiners strangers_meet_joiners_strangers_meet_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_joiners
    ADD CONSTRAINT strangers_meet_joiners_strangers_meet_request_id_fkey FOREIGN KEY (strangers_meet_request_id) REFERENCES public.strangers_meet_requests(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: strangers_meet_joiners strangers_meet_joiners_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_joiners
    ADD CONSTRAINT strangers_meet_joiners_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: strangers_meet_requests strangers_meet_requests_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: strangers_meet_requests strangers_meet_requests_venue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.strangers_meet_requests
    ADD CONSTRAINT strangers_meet_requests_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES public.venues(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: user_interests user_interests_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_interests
    ADD CONSTRAINT user_interests_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: user_matches user_matches_user1_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_matches
    ADD CONSTRAINT user_matches_user1_id_fkey FOREIGN KEY (user1_id) REFERENCES public.users(id) ON UPDATE CASCADE;


--
-- Name: user_matches user_matches_user2_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_matches
    ADD CONSTRAINT user_matches_user2_id_fkey FOREIGN KEY (user2_id) REFERENCES public.users(id) ON UPDATE CASCADE;


--
-- Name: user_matches user_matches_venue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_matches
    ADD CONSTRAINT user_matches_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES public.venues(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: user_penalties user_penalties_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_penalties
    ADD CONSTRAINT user_penalties_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: user_photos user_photos_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_photos
    ADD CONSTRAINT user_photos_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: user_preferences user_preferences_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_preferences
    ADD CONSTRAINT user_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: user_profiles user_profiles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: venue_compliance_logs venue_compliance_logs_venue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venue_compliance_logs
    ADD CONSTRAINT venue_compliance_logs_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES public.venues(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: venue_images venue_images_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venue_images
    ADD CONSTRAINT venue_images_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.users(id) ON UPDATE CASCADE;


--
-- Name: venue_images venue_images_venue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venue_images
    ADD CONSTRAINT venue_images_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES public.venues(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: venues venues_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venues
    ADD CONSTRAINT venues_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict hAgO9zQwPk1ovVr7vyriW7GDwcouSuxyOSEJrkLLN0moHAa8RtnpSwGGpxR1Zr8

