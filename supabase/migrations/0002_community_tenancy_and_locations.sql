-- ============================================================
-- SHIMPI JODI — schema v2 addendum
-- Adds: (1) community tenancy  (2) per-community sub-caste
--       (3) multi-location model  (4) gender hard rule
-- Apply AFTER shimpi-jodi-schema.sql
-- ============================================================

-- ============================================================
-- 1. COMMUNITIES  — the real tenant boundary
-- ============================================================
-- One row per community you launch. "Maratha Jodi" is a row, not a fork.
CREATE TABLE communities (
  id             uuid PRIMARY KEY DEFAULT uuid_v7(),
  name           text NOT NULL,              -- 'Shimpi'
  slug           text NOT NULL UNIQUE,       -- 'shimpi'
  app_name       text NOT NULL,              -- 'Shimpi Jodi'
  domain         text UNIQUE,                -- shimpijodi.in
  -- brand overrides; defaults inherit the base palette
  brand          jsonb NOT NULL DEFAULT '{}',-- {"primary":"#1E3548","accent":"#F4633A","logo_key":"..."}
  default_locale text NOT NULL DEFAULT 'en',
  locales        text[] NOT NULL DEFAULT '{en,mr,hi}',
  is_active      boolean NOT NULL DEFAULT true,
  launched_at    timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now()
);

INSERT INTO communities (name, slug, app_name, domain, launched_at)
VALUES ('Shimpi','shimpi','Shimpi Jodi','shimpijodi.in', now());

-- ------------------------------------------------------------
-- Stamp community_id onto every tenant-scoped table.
-- Backfill to Shimpi, then enforce NOT NULL.
-- ------------------------------------------------------------
DO $$
DECLARE
  c uuid := (SELECT id FROM communities WHERE slug='shimpi');
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'regions','users','profiles','interests','conversations','reports',
    'import_batches','extracted_drafts','admin_users','subscriptions','payments'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ADD COLUMN community_id uuid REFERENCES communities(id)', t);
    EXECUTE format('UPDATE %I SET community_id = %L', t, c);
    EXECUTE format('ALTER TABLE %I ALTER COLUMN community_id SET NOT NULL', t);
    EXECUTE format('CREATE INDEX idx_%s_community ON %I(community_id)', t, t);
  END LOOP;
END $$;

-- Regions are now per-community (Marathwada exists separately for each)
ALTER TABLE regions DROP CONSTRAINT regions_slug_key;
ALTER TABLE regions ADD CONSTRAINT uq_region_community UNIQUE (community_id, slug);

-- Email uniqueness is per-community: the same person may join two communities
ALTER TABLE users DROP CONSTRAINT users_email_key;
ALTER TABLE users ADD CONSTRAINT uq_user_email_community UNIQUE (community_id, email);

-- ============================================================
-- 2. SUB-CASTE, PER COMMUNITY
-- ============================================================
-- Only this table's CONTENT differs between Shimpi and Maratha.
-- No schema change is ever needed to launch a new community.
DROP TABLE IF EXISTS sub_communities CASCADE;
CREATE TABLE sub_communities (
  id           uuid PRIMARY KEY DEFAULT uuid_v7(),
  community_id uuid NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  label        text NOT NULL,
  label_mr     text,
  position     smallint NOT NULL DEFAULT 0,
  is_active    boolean NOT NULL DEFAULT true,
  UNIQUE (community_id, label)
);

ALTER TABLE profiles ADD COLUMN sub_community_id uuid REFERENCES sub_communities(id);
CREATE INDEX idx_profiles_subcomm ON profiles(sub_community_id) WHERE deleted_at IS NULL;

-- Guard: a profile's sub-caste must belong to its own community
CREATE OR REPLACE FUNCTION check_sub_community() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.sub_community_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM sub_communities s
    WHERE s.id = NEW.sub_community_id AND s.community_id = NEW.community_id
  ) THEN
    RAISE EXCEPTION 'sub_community % does not belong to community %',
      NEW.sub_community_id, NEW.community_id;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_check_sub_community
  BEFORE INSERT OR UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION check_sub_community();

-- ============================================================
-- 3. GENDER HARD RULE  — opposite-gender matching only
-- ============================================================
CREATE OR REPLACE FUNCTION check_interest_valid() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE s record; r record;
BEGIN
  SELECT gender, community_id INTO s FROM profiles WHERE id = NEW.sender_profile_id;
  SELECT gender, community_id INTO r FROM profiles WHERE id = NEW.receiver_profile_id;

  IF s.community_id <> r.community_id THEN
    RAISE EXCEPTION 'cross-community interest is not permitted';
  END IF;
  IF s.gender = r.gender THEN
    RAISE EXCEPTION 'opposite-gender matching only';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_check_interest
  BEFORE INSERT ON interests
  FOR EACH ROW EXECUTE FUNCTION check_interest_valid();

-- ============================================================
-- 4. LOCATION MODEL
-- ============================================================
-- Two distinct things, kept separate:
--   (a) WHERE THEY ARE      → typed facts on the profile
--   (b) WHERE THEY'LL SETTLE→ intent + a list of acceptable cities
-- ------------------------------------------------------------

CREATE TYPE settle_intent_t AS ENUM (
  'stay_current',      -- wants to remain where they live now
  'return_hometown',   -- wants to move back to native place
  'open_to_move',      -- flexible, has preferred cities
  'must_move'          -- will definitely relocate (job, family)
);

CREATE TYPE location_pref_t AS ENUM (
  'preferred',         -- would like to settle here
  'acceptable'         -- willing to migrate here if needed
);

-- (a) Where they are — three typed, nullable facts.
ALTER TABLE profiles
  ADD COLUMN residence_city_id uuid REFERENCES cities(id),   -- lives here now
  ADD COLUMN work_city_id      uuid REFERENCES cities(id),   -- works here (often = residence)
  ADD COLUMN work_country      text DEFAULT 'India';         -- for NRI / Gulf profiles
-- native_city_id already exists = hometown

-- Migrate the old single city column, then retire it
UPDATE profiles SET residence_city_id = city_id WHERE residence_city_id IS NULL;
ALTER TABLE profiles RENAME COLUMN city_id TO city_id_deprecated;

CREATE INDEX idx_profiles_residence ON profiles(residence_city_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_profiles_work      ON profiles(work_city_id)      WHERE deleted_at IS NULL;
CREATE INDEX idx_profiles_native    ON profiles(native_city_id)    WHERE deleted_at IS NULL;

-- (b) Where they'll settle — intent + city list
ALTER TABLE profiles
  ADD COLUMN settle_intent settle_intent_t NOT NULL DEFAULT 'open_to_move',
  ADD COLUMN abroad_ok     boolean NOT NULL DEFAULT false;

-- One row per city the member will consider. Handles both
-- "want to continue in X" and "willing to migrate to X".
CREATE TABLE profile_location_prefs (
  profile_id  uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  city_id     uuid NOT NULL REFERENCES cities(id),
  pref_type   location_pref_t NOT NULL,
  position    smallint NOT NULL DEFAULT 0,
  PRIMARY KEY (profile_id, city_id)
);
-- Answers "who would move to Mumbai?" in one index hit
CREATE INDEX idx_locpref_city ON profile_location_prefs(city_id, pref_type);

-- ============================================================
-- 5. TENANT ISOLATION VIA RLS
-- ============================================================
-- API sets on every connection:
--   SET LOCAL app.current_community_id = '<uuid>';
CREATE OR REPLACE FUNCTION current_community_id() RETURNS uuid
  LANGUAGE sql STABLE AS
  $$ SELECT nullif(current_setting('app.current_community_id', true),'')::uuid $$;

ALTER TABLE users    ENABLE ROW LEVEL SECURITY;
ALTER TABLE interests ENABLE ROW LEVEL SECURITY;
ALTER TABLE regions  ENABLE ROW LEVEL SECURITY;

-- Every tenant-scoped read is fenced by community.
-- Super admin (you) bypasses by setting app.current_admin_role='super_admin'.
CREATE POLICY p_tenant_profiles ON profiles
  USING (is_super_admin() OR community_id = current_community_id());
CREATE POLICY p_tenant_users ON users
  USING (is_super_admin() OR community_id = current_community_id());
CREATE POLICY p_tenant_interests ON interests
  USING (is_super_admin() OR community_id = current_community_id());
CREATE POLICY p_tenant_regions ON regions
  USING (is_super_admin() OR community_id = current_community_id());

-- Admins are fenced by BOTH community and region
CREATE OR REPLACE FUNCTION admin_has_region(r uuid) RETURNS boolean
  LANGUAGE sql STABLE AS $$
    SELECT is_super_admin() OR EXISTS (
      SELECT 1
      FROM admin_region_scopes s
      JOIN regions g ON g.id = s.region_id
      WHERE s.admin_user_id = current_admin_id()
        AND s.region_id     = r
        AND g.community_id  = current_community_id()
    );
  $$;

-- ============================================================
-- 6. FEED VIEW  — tenancy + gender rule applied once, centrally
-- ============================================================
DROP VIEW IF EXISTS v_active_profiles;
CREATE VIEW v_active_profiles AS
SELECT
  p.*,
  profile_age(p.date_of_birth)              AS age,
  rc.name  AS residence_city,
  wc.name  AS work_city,
  nc.name  AS native_city,
  sc.label AS sub_community
FROM profiles p
JOIN users u        ON u.id = p.user_id
LEFT JOIN cities rc ON rc.id = p.residence_city_id
LEFT JOIN cities wc ON wc.id = p.work_city_id
LEFT JOIN cities nc ON nc.id = p.native_city_id
LEFT JOIN sub_communities sc ON sc.id = p.sub_community_id
WHERE p.deleted_at IS NULL
  AND u.deleted_at IS NULL
  AND p.status = 'published';

-- Candidate pool for a given member: same community, opposite gender,
-- not blocked either way, no interest already exchanged.
CREATE OR REPLACE FUNCTION candidates_for(p_profile uuid)
RETURNS SETOF v_active_profiles LANGUAGE sql STABLE AS $$
  SELECT v.*
  FROM v_active_profiles v, profiles me
  WHERE me.id = p_profile
    AND v.community_id = me.community_id
    AND v.gender <> me.gender
    AND v.id <> me.id
    AND NOT EXISTS (SELECT 1 FROM blocks b
                    WHERE (b.blocker_profile_id = me.id AND b.blocked_profile_id = v.id)
                       OR (b.blocker_profile_id = v.id  AND b.blocked_profile_id = me.id))
    AND NOT EXISTS (SELECT 1 FROM interests i
                    WHERE (i.sender_profile_id = me.id AND i.receiver_profile_id = v.id)
                       OR (i.sender_profile_id = v.id  AND i.receiver_profile_id = me.id));
$$;

-- ============================================================
-- 7. SEED — Shimpi sub-castes (replace with your real list)
-- ============================================================
INSERT INTO sub_communities (community_id, label, position)
SELECT c.id, x.label, x.pos
FROM communities c,
     (VALUES ('Namdev Shimpi',1),('Moti Shimpi',2),('Saitwal Shimpi',3),
             ('Konkani Shimpi',4),('Other',9)) AS x(label,pos)
WHERE c.slug = 'shimpi';

-- Launching a new community later is exactly this much work:
-- INSERT INTO communities (name,slug,app_name,domain)
--   VALUES ('Maratha','maratha','Maratha Jodi','marathajodi.in');
-- INSERT INTO sub_communities (community_id,label,position) VALUES (...);
-- INSERT INTO regions (community_id,name,slug) VALUES (...);
-- Point the domain at the same app. No code change.
