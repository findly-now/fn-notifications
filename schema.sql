-- =============================================================================
-- FN-Notifications Database Schema
-- =============================================================================
-- This schema defines the complete database structure for the FN-Notifications
-- microservice. It's designed for single-step initialization and can be applied
-- multiple times safely using IF NOT EXISTS clauses and DO blocks for constraints.
--
-- Structure:
-- 1. Extensions
-- 2. Table Definitions
-- 3. Performance Indexes
-- 4. Data Constraints
-- 5. Test Data (optional)
-- =============================================================================

-- =============================================================================
-- EXTENSIONS
-- =============================================================================
-- Enable UUID extension for generating unique identifiers
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- TABLE DEFINITIONS
-- =============================================================================

-- Notifications table - Core entity for managing notification lifecycle
-- Supports multiple channels (email, SMS, WhatsApp) with retry logic and scheduling
CREATE TABLE IF NOT EXISTS notifications (
    id character varying NOT NULL,                                    -- Unique notification identifier
    user_id character varying NOT NULL,                              -- Target user for notification
    channel character varying NOT NULL,                              -- Delivery channel: email, sms, whatsapp
    status character varying DEFAULT 'pending'::character varying NOT NULL, -- Current status in delivery pipeline
    title character varying(255) NOT NULL,                          -- Notification subject/title
    body text NOT NULL,                                              -- Main notification content
    metadata jsonb DEFAULT '{}'::jsonb,                             -- Additional data (deduplication_key, template_vars, etc.)
    scheduled_at timestamp without time zone,                        -- When to send (null = immediate)
    sent_at timestamp without time zone,                            -- When notification was sent
    delivered_at timestamp without time zone,                       -- When delivery was confirmed
    failed_at timestamp without time zone,                          -- When delivery failed
    failure_reason character varying(500),                          -- Error message for failed deliveries
    retry_count integer DEFAULT 0 NOT NULL,                         -- Current retry attempt
    max_retries integer DEFAULT 3 NOT NULL,                         -- Maximum retry attempts allowed
    inserted_at timestamp without time zone NOT NULL,               -- Record creation timestamp
    updated_at timestamp without time zone NOT NULL,                -- Last modification timestamp
    CONSTRAINT notifications_pkey PRIMARY KEY (id)
);

-- User preferences table - Per-user notification settings and contact information
-- Stores user contact details and notification preferences in one place
CREATE TABLE IF NOT EXISTS user_preferences (
    id character varying NOT NULL,                                    -- Unique preference record identifier
    user_id character varying NOT NULL,                              -- User identifier (one record per user)
    global_enabled boolean DEFAULT true NOT NULL,                    -- Master switch for all notifications
    email character varying(255),                                    -- User's email address for email notifications
    phone character varying(50),                                     -- User's phone number for SMS/WhatsApp (E.164 format recommended)
    timezone character varying DEFAULT 'UTC'::character varying NOT NULL, -- User's timezone for scheduling
    language character varying DEFAULT 'en'::character varying NOT NULL,  -- Preferred language for notifications
    channel_preferences jsonb DEFAULT '{}'::jsonb,                   -- Per-channel settings (email: {enabled: true}, etc.)
    inserted_at timestamp without time zone NOT NULL,               -- Record creation timestamp
    updated_at timestamp without time zone NOT NULL,                -- Last modification timestamp
    CONSTRAINT user_preferences_pkey PRIMARY KEY (id)
);

-- =============================================================================
-- PERFORMANCE INDEXES
-- =============================================================================
-- Optimized index set focusing on actual query patterns while minimizing
-- write performance impact. Reduced from 16 to 7 essential indexes.

-- Essential single-column index for user lookups (most frequent query)
CREATE INDEX IF NOT EXISTS notifications_user_id_index ON notifications USING btree (user_id);

-- Composite indexes for actual application query patterns
CREATE INDEX IF NOT EXISTS notifications_user_id_status_index ON notifications USING btree (user_id, status);
    -- ^ Supports: "Get user's pending/failed notifications"

CREATE INDEX IF NOT EXISTS notifications_user_id_channel_index ON notifications USING btree (user_id, channel);
    -- ^ Supports: "Get user's email/SMS notifications"

CREATE INDEX IF NOT EXISTS notifications_status_scheduled_at_index ON notifications USING btree (status, scheduled_at);
    -- ^ Supports: "Find pending notifications ready to send" (job processing)

-- Specialized partial indexes for specific business logic
CREATE INDEX IF NOT EXISTS notifications_retry_eligible_idx ON notifications USING btree (failed_at)
    WHERE ((status)::text = 'failed'::text) AND (retry_count < max_retries);
    -- ^ Optimizes retry job: "Find failed notifications eligible for retry"

CREATE INDEX IF NOT EXISTS notifications_deduplication_idx ON notifications USING btree (((metadata ->> 'deduplication_key'::text)), inserted_at);
    -- ^ Supports deduplication: "Check if notification with same key already exists"

-- User preferences - only the essential unique constraint
CREATE UNIQUE INDEX IF NOT EXISTS user_preferences_user_id_index ON user_preferences USING btree (user_id);
    -- ^ Ensures one preference record per user + optimizes lookups

-- =============================================================================
-- DATA CONSTRAINTS
-- =============================================================================
-- Using DO blocks to add constraints idempotently - this allows the schema
-- to be applied multiple times without errors, which is essential for
-- development environments and deployment automation.

-- Notifications table constraints
DO $$
BEGIN
  -- Validate notification channels - only allow supported delivery methods
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'notifications_channel_check') THEN
    ALTER TABLE notifications ADD CONSTRAINT notifications_channel_check
    CHECK (((channel)::text = ANY (ARRAY[('email'::character varying)::text, ('sms'::character varying)::text, ('whatsapp'::character varying)::text])));
  END IF;

  -- Validate notification status - ensure status follows the defined workflow
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'notifications_status_check') THEN
    ALTER TABLE notifications ADD CONSTRAINT notifications_status_check
    CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('sent'::character varying)::text, ('delivered'::character varying)::text, ('failed'::character varying)::text, ('cancelled'::character varying)::text])));
  END IF;

  -- Ensure retry count is within valid bounds
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'notifications_retry_count_check') THEN
    ALTER TABLE notifications ADD CONSTRAINT notifications_retry_count_check
    CHECK ((retry_count >= 0) AND (retry_count <= max_retries));
  END IF;

  -- Ensure max_retries is non-negative
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'notifications_max_retries_check') THEN
    ALTER TABLE notifications ADD CONSTRAINT notifications_max_retries_check
    CHECK ((max_retries >= 0));
  END IF;
END
$$;

-- User preferences table constraints
DO $$
BEGIN
  -- Validate supported languages - currently English and Spanish
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'user_preferences_language_check') THEN
    ALTER TABLE user_preferences ADD CONSTRAINT user_preferences_language_check
    CHECK (((language)::text = ANY (ARRAY[('en'::character varying)::text, ('es'::character varying)::text])));
  END IF;

  -- Ensure timezone is not empty - prevents invalid timezone configurations
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'user_preferences_timezone_check') THEN
    ALTER TABLE user_preferences ADD CONSTRAINT user_preferences_timezone_check
    CHECK ((length((timezone)::text) > 0));
  END IF;
END
$$;

-- =============================================================================
-- OBAN JOB PROCESSING TABLES
-- =============================================================================
-- Tables required for Oban job processing (background job queues)
-- These support the notification retry worker and other background tasks

-- Create custom enum type for job states first
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'oban_job_state') THEN
    CREATE TYPE oban_job_state AS ENUM ('available', 'scheduled', 'executing', 'retryable', 'completed', 'discarded', 'cancelled');
  END IF;
END
$$;

-- Main job queue table
CREATE TABLE IF NOT EXISTS oban_jobs (
    id bigint NOT NULL,
    state oban_job_state DEFAULT 'available'::oban_job_state NOT NULL,
    queue text DEFAULT 'default'::text NOT NULL,
    worker text NOT NULL,
    args jsonb DEFAULT '{}'::jsonb NOT NULL,
    errors jsonb[] DEFAULT '{}'::jsonb[] NOT NULL,
    attempt integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 20 NOT NULL,
    inserted_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    scheduled_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    attempted_at timestamp without time zone,
    completed_at timestamp without time zone,
    attempted_by text[],
    discarded_at timestamp without time zone,
    priority integer DEFAULT 0 NOT NULL,
    tags character varying(255)[] DEFAULT '{}'::character varying[],
    meta jsonb DEFAULT '{}'::jsonb,
    cancelled_at timestamp without time zone,
    CONSTRAINT oban_jobs_pkey PRIMARY KEY (id)
);

-- Distributed coordination table for Oban peers
CREATE TABLE IF NOT EXISTS oban_peers (
    name text NOT NULL,
    node text NOT NULL,
    started_at timestamp without time zone NOT NULL,
    expires_at timestamp without time zone NOT NULL,
    CONSTRAINT oban_peers_pkey PRIMARY KEY (name)
);

-- Oban job sequence for auto-incrementing IDs
CREATE SEQUENCE IF NOT EXISTS oban_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- Set sequence ownership
ALTER SEQUENCE oban_jobs_id_seq OWNED BY oban_jobs.id;

-- Set default value for ID column
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'oban_jobs'
    AND column_name = 'id'
    AND column_default LIKE 'nextval%'
  ) THEN
    ALTER TABLE oban_jobs ALTER COLUMN id SET DEFAULT nextval('oban_jobs_id_seq'::regclass);
  END IF;
END
$$;

-- Essential Oban indexes for performance
CREATE INDEX IF NOT EXISTS oban_jobs_args_index ON oban_jobs USING gin (args);
CREATE INDEX IF NOT EXISTS oban_jobs_meta_index ON oban_jobs USING gin (meta);
CREATE INDEX IF NOT EXISTS oban_jobs_state_queue_priority_scheduled_at_id_index ON oban_jobs USING btree (state, queue, priority, scheduled_at, id);
CREATE UNIQUE INDEX IF NOT EXISTS oban_jobs_unique_scheduled_index ON oban_jobs USING btree (worker, args, meta) WHERE (state = 'scheduled'::oban_job_state);

-- =============================================================================
-- TEST DATA (OPTIONAL)
-- =============================================================================
-- Uncomment the following section to load sample data for development/testing
-- This data represents typical scenarios for the notification system


-- Sample user preferences with contact information
-- Sample user preferences with real contact information for testing
-- WARNING: These are real email/phone formats - replace with your own test data
INSERT INTO user_preferences (id, user_id, global_enabled, email, phone, timezone, language, channel_preferences, inserted_at, updated_at)
VALUES
    ('pref_1', 'test-user', true, 'jsarabia.dev@gmail.com', '+1234567890', 'America/New_York', 'en', '{"email": {"enabled": true}, "sms": {"enabled": true}, "whatsapp": {"enabled": false}}', NOW(), NOW()),
    ('pref_2', 'user_123', true, 'jsarabia.dev@gmail.com', '+1234567890', 'America/New_York', 'en', '{"email": {"enabled": true}, "sms": {"enabled": false}}', NOW(), NOW()),
    ('pref_3', 'user_456', true, 'jane.smith@example.com', '+56994599483', 'Europe/Madrid', 'es', '{"email": {"enabled": true}, "sms": {"enabled": true}, "whatsapp": {"enabled": true}}', NOW(), NOW()),
    ('pref_4', 'user_789', false, 'disabled.user@example.com', '+19876543210', 'UTC', 'en', '{}', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

-- Sample notifications covering different scenarios
-- Note: Contact information now comes from user_preferences table, not stored here
INSERT INTO notifications (id, user_id, channel, status, title, body, metadata, scheduled_at, retry_count, max_retries, inserted_at, updated_at)
VALUES
    -- Pending email notification
    ('notif_1', 'user_123', 'email', 'pending', 'Welcome!', 'Welcome to our platform', '{"deduplication_key": "welcome_user_123"}', NULL, 0, 3, NOW(), NOW()),

    -- Scheduled SMS notification
    ('notif_2', 'user_456', 'sms', 'pending', 'Reminder', 'You have a meeting tomorrow', '{"deduplication_key": "meeting_reminder_456"}', NOW() + INTERVAL '1 hour', 0, 3, NOW(), NOW()),

    -- Failed WhatsApp notification with retry
    ('notif_3', 'user_456', 'whatsapp', 'failed', 'Alert', 'Important update available', '{"template_id": "alert_template"}', NULL, 1, 3, NOW(), NOW()),

    -- Successfully delivered notification
    ('notif_4', 'user_123', 'email', 'delivered', 'Confirmation', 'Your order has been confirmed', '{"order_id": "ORD-12345"}', NULL, 0, 3, NOW() - INTERVAL '1 day', NOW())
ON CONFLICT (id) DO NOTHING;

