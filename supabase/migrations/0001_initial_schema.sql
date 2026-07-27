-- ============================================================
-- SHIMPI JODI — PostgreSQL schema v1
-- Engine: PostgreSQL 16
-- Model : single shared member pool + region-scoped admin RBAC
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "citext";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- UUID v7 (time-ordered). Replace with pg_uuidv7 extension if available.
CREATE OR REPLACE FUNCTION uuid_v7() RETURNS uuid AS $$
  SELECT encode(
    set_bit(set_bit(overlay(uuid_send(gen_random_uuid())
      PLACING substring(int8send(floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint) FROM 3)
      FROM 1 FOR 6), 52, 1), 53, 1), 'hex')::uuid;
$$ LANGUAGE sql VOLATILE;

-- ============================================================
-- 1. ENUMS
-- ============================================================
CREATE TYPE admin_role        AS ENUM ('super_admin','region_admin','moderator');
CREATE TYPE user_status       AS ENUM ('invited','active','suspended','deleted');
CREATE TYPE profile_status    AS ENUM ('draft','pending_review','claim_sent','published','hidden','suspended','deleted');
CREATE TYPE gender_t          AS ENUM ('male','female');
CREATE TYPE family_type_t     AS ENUM ('nuclear','joint');
CREATE TYPE diet_t            AS ENUM ('vegetarian','non_vegetarian','eggetarian','vegan');
CREATE TYPE horoscope_pref_t  AS ENUM ('important','flexible','not_important');
CREATE TYPE marital_status_t  AS ENUM ('never_married','divorced','widowed');
CREATE TYPE media_kind        AS ENUM ('photo','video_intro');
CREATE TYPE media_status      AS ENUM ('uploaded','processing','ready','failed','rejected');
CREATE TYPE moderation_status AS ENUM ('pending','approved','rejected');
CREATE TYPE interest_intent   AS ENUM ('impressed','families_aligned','would_like_to_talk');
CREATE TYPE interest_status   AS ENUM ('pending','accepted','declined','withdrawn','expired');
CREATE TYPE conversation_status AS ENUM ('locked','open','closed');
CREATE TYPE subscription_status AS ENUM ('active','expired','cancelled','pending');
CREATE TYPE payment_status    AS ENUM ('created','pending','paid','failed','refunded');
CREATE TYPE consent_type      AS ENUM ('publish_profile','store_personal_data','email_notifications','family_managed');
CREATE TYPE report_status     AS ENUM ('new','reviewing','actioned','dismissed');
CREATE TYPE draft_status      AS ENUM ('pending_review','approved','rejected','claim_sent','claimed');
CREATE TYPE data_request_type AS ENUM ('export','erasure');

-- ============================================================
-- 2. LOOKUPS  (filter integrity: FKs, never free text)
-- ============================================================
CREATE TABLE regions (
  id          uuid PRIMARY KEY DEFAULT uuid_v7(),
  name        text NOT NULL,
  slug        text NOT NULL UNIQUE,
  state       text NOT NULL DEFAULT 'Maharashtra',
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE cities (
  id          uuid PRIMARY KEY DEFAULT uuid_v7(),
  name        text NOT NULL,
  region_id   uuid NOT NULL REFERENCES regions(id),
  state       text NOT NULL DEFAULT 'Maharashtra',
  is_active   boolean NOT NULL DEFAULT true,
  UNIQUE (name, state)
);
CREATE INDEX idx_cities_region ON cities(region_id);

CREATE TABLE education_levels (
  id smallserial PRIMARY KEY, label text NOT NULL UNIQUE,
  rank smallint NOT NULL, is_active boolean NOT NULL DEFAULT true
);
CREATE TABLE occupations (
  id smallserial PRIMARY KEY, label text NOT NULL UNIQUE,
  category text, is_active boolean NOT NULL DEFAULT true
);
CREATE TABLE income_bands (
  id smallserial PRIMARY KEY, label text NOT NULL UNIQUE,
  min_lpa numeric(6,2), max_lpa numeric(6,2),
  rank smallint NOT NULL, is_active boolean NOT NULL DEFAULT true
);
CREATE TABLE mother_tongues (
  id smallserial PRIMARY KEY, label text NOT NULL UNIQUE,
  is_active boolean NOT NULL DEFAULT true
);
-- Optional but decide NOW, not later (see design doc §7)
CREATE TABLE sub_communities (
  id smallserial PRIMARY KEY, label text NOT NULL UNIQUE,
  is_active boolean NOT NULL DEFAULT true
);
CREATE TABLE prompts (
  id smallserial PRIMARY KEY,
  text_en text NOT NULL, text_mr text, text_hi text, text_te text,
  is_active boolean NOT NULL DEFAULT true, position smallint NOT NULL DEFAULT 0
);

-- ============================================================
-- 3. ADMINS  (region-scoped RBAC)
-- ============================================================
CREATE TABLE admin_users (
  id            uuid PRIMARY KEY DEFAULT uuid_v7(),
  email         citext NOT NULL UNIQUE,
  full_name     text NOT NULL,
  role          admin_role NOT NULL,
  password_hash text,
  totp_secret   text,                        -- 2FA mandatory for super_admin
  is_active     boolean NOT NULL DEFAULT true,
  last_login_at timestamptz,
  created_by    uuid REFERENCES admin_users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz,
  deleted_by    uuid REFERENCES admin_users(id)
);

CREATE TABLE admin_region_scopes (
  admin_user_id uuid NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
  region_id     uuid NOT NULL REFERENCES regions(id),
  granted_by    uuid REFERENCES admin_users(id),
  granted_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (admin_user_id, region_id)
);

-- ============================================================
-- 4. MEMBERS
-- ============================================================
CREATE TABLE users (
  id                uuid PRIMARY KEY DEFAULT uuid_v7(),
  email             citext NOT NULL UNIQUE,
  email_verified_at timestamptz,
  phone             text,
  status            user_status NOT NULL DEFAULT 'invited',
  locale            text NOT NULL DEFAULT 'en',   -- en | mr | hi | te
  last_active_at    timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,
  deleted_by        uuid REFERENCES admin_users(id),
  delete_reason     text
);
CREATE INDEX idx_users_active ON users(last_active_at DESC) WHERE deleted_at IS NULL;

CREATE TABLE auth_otps (
  id         uuid PRIMARY KEY DEFAULT uuid_v7(),
  user_id    uuid REFERENCES users(id) ON DELETE CASCADE,
  email      citext NOT NULL,
  code_hash  text NOT NULL,
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  attempts   smallint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_otp_email ON auth_otps(email, created_at DESC);

CREATE TABLE profiles (
  id                 uuid PRIMARY KEY DEFAULT uuid_v7(),
  user_id            uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE RESTRICT,
  region_id          uuid NOT NULL REFERENCES regions(id),

  first_name         text NOT NULL,
  last_name          text NOT NULL,
  gender             gender_t NOT NULL,
  date_of_birth      date NOT NULL,
  height_cm          smallint NOT NULL CHECK (height_cm BETWEEN 120 AND 220),
  marital_status     marital_status_t NOT NULL DEFAULT 'never_married',

  city_id            uuid REFERENCES cities(id),
  native_city_id     uuid REFERENCES cities(id),
  education_id       smallint REFERENCES education_levels(id),
  occupation_id      smallint REFERENCES occupations(id),
  employer           text,
  income_band_id     smallint REFERENCES income_bands(id),
  mother_tongue_id   smallint REFERENCES mother_tongues(id),
  sub_community_id   smallint REFERENCES sub_communities(id),

  family_type        family_type_t,
  diet               diet_t,
  horoscope_pref     horoscope_pref_t,
  open_to_relocate   boolean,
  about              text CHECK (char_length(about) <= 600),

  status             profile_status NOT NULL DEFAULT 'draft',
  completion_score   smallint NOT NULL DEFAULT 0 CHECK (completion_score BETWEEN 0 AND 100),
  is_verified        boolean NOT NULL DEFAULT false,
  verified_by        uuid REFERENCES admin_users(id),
  managed_by_admin_id uuid REFERENCES admin_users(id),  -- which admin sourced this profile

  published_at       timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  deleted_at         timestamptz,
  deleted_by         uuid REFERENCES admin_users(id),

  search_vector      tsvector GENERATED ALWAYS AS (
                       to_tsvector('simple',
                         coalesce(first_name,'')||' '||coalesce(last_name,'')||' '||coalesce(employer,''))
                     ) STORED
);

-- Age is derived, never stored
CREATE OR REPLACE FUNCTION profile_age(dob date) RETURNS int
  LANGUAGE sql IMMUTABLE AS $$ SELECT date_part('year', age(dob))::int $$;

-- The feed's covering index. Order matters: equality cols first, range last.
CREATE INDEX idx_profiles_feed ON profiles
  (gender, status, region_id, date_of_birth, height_cm)
  WHERE deleted_at IS NULL AND status = 'published';
CREATE INDEX idx_profiles_city      ON profiles(city_id)      WHERE deleted_at IS NULL;
CREATE INDEX idx_profiles_education ON profiles(education_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_profiles_income    ON profiles(income_band_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_profiles_region    ON profiles(region_id)    WHERE deleted_at IS NULL;
CREATE INDEX idx_profiles_search    ON profiles USING gin(search_vector);

CREATE TABLE profile_family (
  profile_id        uuid PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  father_occupation text,
  mother_occupation text,
  brothers          smallint DEFAULT 0,
  sisters           smallint DEFAULT 0,
  siblings_married  smallint DEFAULT 0,
  family_notes      text CHECK (char_length(family_notes) <= 400),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE profile_preferences (
  profile_id         uuid PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  age_min            smallint, age_max smallint,
  height_min_cm      smallint, height_max_cm smallint,
  preferred_city_ids uuid[]    DEFAULT '{}',
  min_education_id   smallint  REFERENCES education_levels(id),
  min_income_band_id smallint  REFERENCES income_bands(id),
  family_type        family_type_t,
  diet               diet_t,
  relocation_ok      boolean,
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CHECK (age_min IS NULL OR age_max IS NULL OR age_min <= age_max)
);

CREATE TABLE profile_prompts (
  id         uuid PRIMARY KEY DEFAULT uuid_v7(),
  profile_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  prompt_id  smallint NOT NULL REFERENCES prompts(id),
  answer     text NOT NULL CHECK (char_length(answer) BETWEEN 3 AND 140),
  position   smallint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (profile_id, prompt_id)
);
CREATE INDEX idx_prompts_profile ON profile_prompts(profile_id, position);

-- ============================================================
-- 5. MEDIA  (photos + 60s video intro)
-- ============================================================
CREATE TABLE media_assets (
  id                uuid PRIMARY KEY DEFAULT uuid_v7(),
  profile_id        uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  kind              media_kind NOT NULL,
  storage_key       text NOT NULL,            -- object-storage path of the ORIGINAL
  mime_type         text NOT NULL,
  bytes             bigint NOT NULL,
  width             int, height int,
  duration_ms       int,                      -- video only
  blurhash          text,                     -- instant placeholder in the feed
  dominant_color    text,
  is_primary        boolean NOT NULL DEFAULT false,
  position          smallint NOT NULL DEFAULT 0,
  status            media_status NOT NULL DEFAULT 'uploaded',
  moderation_status moderation_status NOT NULL DEFAULT 'pending',
  moderated_by      uuid REFERENCES admin_users(id),
  moderated_at      timestamptz,
  processing_error  text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,
  deleted_by        uuid REFERENCES admin_users(id),

  CHECK (kind <> 'video_intro' OR duration_ms IS NULL OR duration_ms <= 60000)
);
CREATE INDEX idx_media_profile ON media_assets(profile_id, kind, position)
  WHERE deleted_at IS NULL AND status = 'ready';
-- exactly one primary photo, one video intro per profile
CREATE UNIQUE INDEX uq_media_primary ON media_assets(profile_id)
  WHERE is_primary AND kind = 'photo' AND deleted_at IS NULL;
CREATE UNIQUE INDEX uq_media_video ON media_assets(profile_id)
  WHERE kind = 'video_intro' AND deleted_at IS NULL;

CREATE TABLE media_variants (
  id             uuid PRIMARY KEY DEFAULT uuid_v7(),
  media_asset_id uuid NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
  variant        text NOT NULL,   -- thumb|card|full|poster|hls_360|hls_540|hls_720
  format         text NOT NULL,   -- avif|webp|jpeg|hls
  storage_key    text NOT NULL,
  width int, height int, bytes bigint, bitrate_kbps int,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (media_asset_id, variant, format)
);

-- ============================================================
-- 6. INTERACTIONS
-- ============================================================
CREATE TABLE interests (
  id                  uuid PRIMARY KEY DEFAULT uuid_v7(),
  sender_profile_id   uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  receiver_profile_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  intent              interest_intent NOT NULL,
  status              interest_status NOT NULL DEFAULT 'pending',
  message             text CHECK (char_length(message) <= 200),
  created_at          timestamptz NOT NULL DEFAULT now(),
  responded_at        timestamptz,
  expires_at          timestamptz DEFAULT now() + interval '30 days',
  CHECK (sender_profile_id <> receiver_profile_id),
  UNIQUE (sender_profile_id, receiver_profile_id)
);
CREATE INDEX idx_interest_recv ON interests(receiver_profile_id, status, created_at DESC);
CREATE INDEX idx_interest_send ON interests(sender_profile_id, status, created_at DESC);

CREATE TABLE shortlists (
  profile_id        uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  target_profile_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (profile_id, target_profile_id),
  CHECK (profile_id <> target_profile_id)
);

CREATE TABLE blocks (
  blocker_profile_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  blocked_profile_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  reason     text,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_profile_id, blocked_profile_id)
);

-- High-volume: partition by month from day one
CREATE TABLE profile_views (
  id                 uuid NOT NULL DEFAULT uuid_v7(),
  viewer_profile_id  uuid NOT NULL,
  viewed_profile_id  uuid NOT NULL,
  viewed_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id, viewed_at)
) PARTITION BY RANGE (viewed_at);
CREATE TABLE profile_views_2026_07 PARTITION OF profile_views
  FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

CREATE TABLE conversations (
  id           uuid PRIMARY KEY DEFAULT uuid_v7(),
  interest_id  uuid NOT NULL UNIQUE REFERENCES interests(id) ON DELETE CASCADE,
  profile_a_id uuid NOT NULL REFERENCES profiles(id),
  profile_b_id uuid NOT NULL REFERENCES profiles(id),
  status       conversation_status NOT NULL DEFAULT 'locked',
  unlocked_at    timestamptz,
  unlocked_by_user_id uuid REFERENCES users(id),   -- who paid to open it
  last_message_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CHECK (profile_a_id < profile_b_id)              -- canonical ordering, prevents dupes
);
CREATE INDEX idx_conv_a ON conversations(profile_a_id, last_message_at DESC);
CREATE INDEX idx_conv_b ON conversations(profile_b_id, last_message_at DESC);

CREATE TABLE messages (
  id                uuid PRIMARY KEY DEFAULT uuid_v7(),
  conversation_id   uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_profile_id uuid NOT NULL REFERENCES profiles(id),
  body              text NOT NULL CHECK (char_length(body) <= 2000),
  read_at           timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);
CREATE INDEX idx_msg_conv ON messages(conversation_id, created_at DESC) WHERE deleted_at IS NULL;

-- ============================================================
-- 7. MONEY
-- ============================================================
CREATE TABLE plans (
  id              smallserial PRIMARY KEY,
  code            text NOT NULL UNIQUE,       -- plus_3m | plus_6m | plus_12m
  label           text NOT NULL,
  duration_months smallint NOT NULL,
  price_paise     integer NOT NULL,           -- integer paise, never float
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE payments (
  id                 uuid PRIMARY KEY DEFAULT uuid_v7(),
  user_id            uuid NOT NULL REFERENCES users(id),
  plan_id            smallint REFERENCES plans(id),
  gateway            text NOT NULL DEFAULT 'razorpay',
  gateway_order_id   text UNIQUE,
  gateway_payment_id text UNIQUE,
  amount_paise       integer NOT NULL,
  currency           text NOT NULL DEFAULT 'INR',
  status             payment_status NOT NULL DEFAULT 'created',
  method             text,
  failure_reason     text,
  raw_response       jsonb,
  created_at         timestamptz NOT NULL DEFAULT now(),
  paid_at            timestamptz
);
CREATE INDEX idx_pay_user ON payments(user_id, created_at DESC);

CREATE TABLE subscriptions (
  id          uuid PRIMARY KEY DEFAULT uuid_v7(),
  user_id     uuid NOT NULL REFERENCES users(id),
  plan_id     smallint NOT NULL REFERENCES plans(id),
  payment_id  uuid REFERENCES payments(id),
  status      subscription_status NOT NULL DEFAULT 'pending',
  started_at  timestamptz,
  expires_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_sub_user ON subscriptions(user_id, status, expires_at DESC);
-- one active subscription per user
CREATE UNIQUE INDEX uq_sub_active ON subscriptions(user_id) WHERE status = 'active';

-- ============================================================
-- 8. COMPLIANCE (DPDP) — append-only
-- ============================================================
CREATE TABLE consents (
  id           uuid PRIMARY KEY DEFAULT uuid_v7(),
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  consent_type consent_type NOT NULL,
  granted      boolean NOT NULL,
  policy_version text NOT NULL,
  ip_address   inet,
  user_agent   text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_consent_user ON consents(user_id, consent_type, created_at DESC);

-- Latest state per consent type
CREATE VIEW v_current_consents AS
SELECT DISTINCT ON (user_id, consent_type)
  user_id, consent_type, granted, policy_version, created_at
FROM consents ORDER BY user_id, consent_type, created_at DESC;

CREATE TABLE data_requests (
  id           uuid PRIMARY KEY DEFAULT uuid_v7(),
  user_id      uuid NOT NULL REFERENCES users(id),
  request_type data_request_type NOT NULL,
  status       text NOT NULL DEFAULT 'pending',
  requested_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  handled_by   uuid REFERENCES admin_users(id),
  export_key   text
);

-- ============================================================
-- 9. MODERATION
-- ============================================================
CREATE TABLE reports (
  id                  uuid PRIMARY KEY DEFAULT uuid_v7(),
  reporter_profile_id uuid NOT NULL REFERENCES profiles(id),
  reported_profile_id uuid NOT NULL REFERENCES profiles(id),
  reason              text NOT NULL,
  details             text,
  status              report_status NOT NULL DEFAULT 'new',
  handled_by          uuid REFERENCES admin_users(id),
  handled_at          timestamptz,
  action_taken        text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  CHECK (reporter_profile_id <> reported_profile_id)
);
CREATE INDEX idx_report_status ON reports(status, created_at DESC);

-- ============================================================
-- 10. PDF EXTRACTION PIPELINE  (add-on, isolated from live data)
-- ============================================================
CREATE TABLE import_batches (
  id                 uuid PRIMARY KEY DEFAULT uuid_v7(),
  uploaded_by_admin_id uuid NOT NULL REFERENCES admin_users(id),
  region_id          uuid NOT NULL REFERENCES regions(id),
  source_filename    text NOT NULL,
  storage_key        text NOT NULL,
  file_count         int NOT NULL DEFAULT 1,
  status             text NOT NULL DEFAULT 'uploaded',
  drafts_created     int NOT NULL DEFAULT 0,
  error              text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  completed_at       timestamptz
);
CREATE INDEX idx_batch_region ON import_batches(region_id, created_at DESC);

CREATE TABLE extracted_drafts (
  id             uuid PRIMARY KEY DEFAULT uuid_v7(),
  batch_id       uuid NOT NULL REFERENCES import_batches(id) ON DELETE CASCADE,
  region_id      uuid NOT NULL REFERENCES regions(id),
  source_page    int,
  raw_text       text,
  extracted      jsonb NOT NULL,      -- normalised to the profile schema
  confidence     jsonb NOT NULL,      -- per-field 0..1 → drives the amber flags in admin UI
  photo_key      text,
  contact_email  citext,
  status         draft_status NOT NULL DEFAULT 'pending_review',
  reviewed_by    uuid REFERENCES admin_users(id),
  reviewed_at    timestamptz,
  reject_reason  text,
  claim_token    text UNIQUE,
  claim_sent_at  timestamptz,
  claim_expires_at timestamptz,
  claimed_at     timestamptz,
  user_id        uuid REFERENCES users(id),   -- set once claimed
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_draft_review ON extracted_drafts(region_id, status, created_at);

-- ============================================================
-- 11. ANALYTICS + AUDIT  (append-only)
-- ============================================================
CREATE TABLE activity_events (
  id             uuid NOT NULL DEFAULT uuid_v7(),
  occurred_at    timestamptz NOT NULL DEFAULT now(),
  actor_user_id  uuid,
  actor_admin_id uuid,
  event_type     text NOT NULL,   -- profile.published | interest.sent | payment.paid | ...
  entity_type    text,
  entity_id      uuid,
  region_id      uuid,
  metadata       jsonb NOT NULL DEFAULT '{}',
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);
CREATE TABLE activity_events_2026_07 PARTITION OF activity_events
  FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE INDEX idx_events_type ON activity_events(event_type, occurred_at DESC);
CREATE INDEX idx_events_region ON activity_events(region_id, occurred_at DESC);

CREATE TABLE audit_log (
  id            uuid PRIMARY KEY DEFAULT uuid_v7(),
  admin_user_id uuid NOT NULL REFERENCES admin_users(id),
  action        text NOT NULL,     -- profile.soft_delete | user.purge | role.grant | ...
  entity_type   text NOT NULL,
  entity_id     uuid,
  before_state  jsonb,
  after_state   jsonb,
  reason        text,
  ip_address    inet,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_admin ON audit_log(admin_user_id, created_at DESC);

-- ============================================================
-- 12. VIEWS  (never trust every query to remember deleted_at)
-- ============================================================
CREATE VIEW v_active_profiles AS
SELECT p.*, profile_age(p.date_of_birth) AS age
FROM profiles p
JOIN users u ON u.id = p.user_id
WHERE p.deleted_at IS NULL
  AND u.deleted_at IS NULL
  AND p.status = 'published';

-- ============================================================
-- 13. ROW-LEVEL SECURITY  (region scoping enforced in the DB)
-- ============================================================
-- Session context set by the API on every connection:
--   SET LOCAL app.current_admin_id   = '<uuid>';
--   SET LOCAL app.current_admin_role = 'region_admin';

CREATE OR REPLACE FUNCTION current_admin_id() RETURNS uuid
  LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.current_admin_id', true),'')::uuid $$;

CREATE OR REPLACE FUNCTION is_super_admin() RETURNS boolean
  LANGUAGE sql STABLE AS $$ SELECT coalesce(current_setting('app.current_admin_role', true),'') = 'super_admin' $$;

CREATE OR REPLACE FUNCTION admin_has_region(r uuid) RETURNS boolean
  LANGUAGE sql STABLE AS $$
    SELECT is_super_admin() OR EXISTS (
      SELECT 1 FROM admin_region_scopes s
      WHERE s.admin_user_id = current_admin_id() AND s.region_id = r);
  $$;

ALTER TABLE profiles          ENABLE ROW LEVEL SECURITY;
ALTER TABLE extracted_drafts  ENABLE ROW LEVEL SECURITY;
ALTER TABLE import_batches    ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_profiles_admin_read ON profiles
  FOR SELECT USING (admin_has_region(region_id));
CREATE POLICY p_profiles_admin_write ON profiles
  FOR UPDATE USING (admin_has_region(region_id));
-- Only super_admin may DELETE. Everyone else must soft-delete.
CREATE POLICY p_profiles_delete ON profiles
  FOR DELETE USING (is_super_admin());

CREATE POLICY p_drafts_scope ON extracted_drafts
  USING (admin_has_region(region_id));
CREATE POLICY p_batches_scope ON import_batches
  USING (admin_has_region(region_id));

-- ============================================================
-- 14. DELETION
-- ============================================================
CREATE OR REPLACE FUNCTION soft_delete_user(p_user uuid, p_admin uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE users SET status='deleted', deleted_at=now(), deleted_by=p_admin, delete_reason=p_reason
    WHERE id=p_user AND deleted_at IS NULL;
  UPDATE profiles SET status='deleted', deleted_at=now(), deleted_by=p_admin WHERE user_id=p_user;
  UPDATE media_assets SET deleted_at=now(), deleted_by=p_admin
    WHERE profile_id IN (SELECT id FROM profiles WHERE user_id=p_user);
  INSERT INTO audit_log(admin_user_id, action, entity_type, entity_id, reason)
    VALUES (p_admin, 'user.soft_delete', 'user', p_user, p_reason);
END $$;

-- Super-admin only. Irreversible. Media purge from object storage is queued by the app.
CREATE OR REPLACE FUNCTION purge_user(p_user uuid, p_admin uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_users WHERE id=p_admin AND role='super_admin' AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'purge_user: super_admin role required';
  END IF;

  INSERT INTO audit_log(admin_user_id, action, entity_type, entity_id, reason, before_state)
    VALUES (p_admin, 'user.purge', 'user', p_user, p_reason,
            (SELECT to_jsonb(u) FROM users u WHERE u.id = p_user));

  UPDATE messages SET body='[removed]', deleted_at=now()
    WHERE sender_profile_id IN (SELECT id FROM profiles WHERE user_id=p_user);
  DELETE FROM media_assets WHERE profile_id IN (SELECT id FROM profiles WHERE user_id=p_user);
  DELETE FROM profiles WHERE user_id=p_user;
  UPDATE users SET email = concat('purged+', id, '@invalid'), phone=NULL, status='deleted'
    WHERE id=p_user;
END $$;

-- ============================================================
-- 15. SEED
-- ============================================================
INSERT INTO regions(name,slug) VALUES
  ('Marathwada','marathwada'),('Western Maharashtra','west-mh'),
  ('Vidarbha','vidarbha'),('Mumbai–Konkan','mumbai-konkan'),('Outside Maharashtra','outside-mh');

INSERT INTO income_bands(label,min_lpa,max_lpa,rank) VALUES
  ('Below ₹5 L',0,5,1),('₹5–8 L',5,8,2),('₹8–12 L',8,12,3),
  ('₹12–18 L',12,18,4),('₹18 L+',18,NULL,5),('Prefer not to say',NULL,NULL,9);

INSERT INTO plans(code,label,duration_months,price_paise) VALUES
  ('plus_3m','Plus — 3 months',3,49900),
  ('plus_6m','Plus — 6 months',6,79900),
  ('plus_12m','Plus — 12 months',12,124900);

INSERT INTO prompts(text_en,position) VALUES
  ('A Sunday at my home looks like…',1),
  ('In marriage, my one non-negotiable is…',2),
  ('My family teases me about…',3),
  ('Something I''m quietly proud of…',4),
  ('I''ll know it''s right when…',5),
  ('The way I unwind is…',6);
