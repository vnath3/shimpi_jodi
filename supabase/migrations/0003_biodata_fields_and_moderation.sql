-- ============================================================
-- SHIMPI JODI — schema v3 addendum
-- (1) fields exposed by real biodata  (2) private data split
-- (3) chat moderation
-- Apply AFTER shimpi-jodi-schema-v2-addendum.sql
-- ============================================================

-- ============================================================
-- 1. NAMING — Indian convention: First + Father's + Surname
-- ============================================================
ALTER TABLE profiles
  ADD COLUMN middle_name text,          -- father's given name: "Dharmendra"
  ADD COLUMN display_name text GENERATED ALWAYS AS (
    first_name || ' ' || coalesce(middle_name || ' ', '') || last_name
  ) STORED;

-- ============================================================
-- 2. BIRTH DETAILS — kundali matching
-- ============================================================
ALTER TABLE profiles
  ADD COLUMN birth_time      time,               -- '15:15'
  ADD COLUMN birth_city_id   uuid REFERENCES cities(id),
  ADD COLUMN birth_city_text text,               -- fallback if not in lookup
  ADD COLUMN blood_group     text CHECK (blood_group IN
    ('A+','A-','B+','B-','O+','O-','AB+','AB-'));

COMMENT ON COLUMN profiles.birth_time IS
  'Optional. Required by families who match kundali — ask at onboarding, do not chase later.';

-- ============================================================
-- 3. EDUCATION & WORK detail
-- ============================================================
ALTER TABLE profiles
  ADD COLUMN education_field text,   -- 'E&TC', 'Computer Science', 'Commerce'
  ADD COLUMN job_title       text,   -- 'Network Engineer' (display; occupation_id filters)
  ADD COLUMN owns_house      boolean;

-- ============================================================
-- 4. FAMILY — names + sibling detail with birth order
-- ============================================================
ALTER TABLE profile_family
  ADD COLUMN father_name text,
  ADD COLUMN mother_name text;

CREATE TYPE sibling_relation_t AS ENUM ('brother','sister');
CREATE TYPE sibling_order_t    AS ENUM ('elder','younger');

CREATE TABLE profile_siblings (
  id           uuid PRIMARY KEY DEFAULT uuid_v7(),
  profile_id   uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  relation     sibling_relation_t NOT NULL,
  birth_order  sibling_order_t NOT NULL,
  is_married   boolean NOT NULL DEFAULT false,
  occupation   text,
  position     smallint NOT NULL DEFAULT 0
);
CREATE INDEX idx_siblings_profile ON profile_siblings(profile_id, position);

-- Old aggregate columns become derived; keep for now, stop writing to them.
COMMENT ON COLUMN profile_family.brothers IS 'DEPRECATED — use profile_siblings';
COMMENT ON COLUMN profile_family.sisters  IS 'DEPRECATED — use profile_siblings';

-- ============================================================
-- 5. PREFERENCES — free text alongside the structured filters
-- ============================================================
ALTER TABLE profile_preferences
  ADD COLUMN expectations_text text CHECK (char_length(expectations_text) <= 200),
  ADD COLUMN wants_own_house   boolean;

-- ============================================================
-- 6. PRIVATE DATA — captured, never published
-- ============================================================
-- Separate table so no careless SELECT * on profiles can leak it.
CREATE TABLE profile_private (
  profile_id      uuid PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  phone           text,
  alt_phone       text,
  address_line    text,          -- 'Zingabai Takli'
  address_city_id uuid REFERENCES cities(id),
  postal_code     text,
  updated_at      timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE profile_private ENABLE ROW LEVEL SECURITY;

-- Only super_admin, or a region admin scoped to that profile's region.
CREATE POLICY p_private_admin ON profile_private
  USING (
    is_super_admin()
    OR EXISTS (SELECT 1 FROM profiles p
               WHERE p.id = profile_private.profile_id
                 AND admin_has_region(p.region_id))
  );

-- Explicit, audited contact release after a mutual accept.
CREATE TABLE contact_shares (
  id              uuid PRIMARY KEY DEFAULT uuid_v7(),
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  shared_by_profile_id uuid NOT NULL REFERENCES profiles(id),
  shared_with_profile_id uuid NOT NULL REFERENCES profiles(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (conversation_id, shared_by_profile_id)
);

-- ============================================================
-- 7. EXTRACTION PROVENANCE
-- ============================================================
ALTER TABLE extracted_drafts
  ADD COLUMN source_ref text,          -- 'TSSK PR. No. 10'
  ADD COLUMN source_org text;          -- 'TSSK'
CREATE INDEX idx_draft_sourceref ON extracted_drafts(source_org, source_ref);

-- ============================================================
-- 8. CHAT MODERATION
-- ============================================================
CREATE TYPE flag_source_t   AS ENUM ('pattern','classifier','user_report','behavioural');
CREATE TYPE flag_category_t AS ENUM
  ('sexual_solicitation','harassment','threat','money_request',
   'contact_leak','external_platform','spam','other');
CREATE TYPE flag_status_t   AS ENUM ('open','upheld','dismissed');
CREATE TYPE mod_action_t    AS ENUM ('warn','mute_chat','suspend','ban','none');

-- Multilingual term list. Seed per language INCLUDING roman transliteration —
-- transliterated Marathi/Hindi is the most common evasion path.
CREATE TABLE moderation_terms (
  id         serial PRIMARY KEY,
  term       text NOT NULL,
  lang       text NOT NULL,            -- en | mr | hi | te | roman
  category   flag_category_t NOT NULL,
  severity   smallint NOT NULL CHECK (severity BETWEEN 1 AND 3), -- 1 warn, 3 block
  is_regex   boolean NOT NULL DEFAULT false,
  is_active  boolean NOT NULL DEFAULT true,
  UNIQUE (term, lang)
);

CREATE TABLE message_flags (
  id           uuid PRIMARY KEY DEFAULT uuid_v7(),
  message_id   uuid REFERENCES messages(id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  subject_profile_id uuid NOT NULL REFERENCES profiles(id),   -- who sent it
  reporter_profile_id uuid REFERENCES profiles(id),           -- null if automated
  source       flag_source_t NOT NULL,
  category     flag_category_t NOT NULL,
  score        numeric(4,3),            -- classifier confidence 0.000–1.000
  matched_term text,                    -- pattern layer only
  status       flag_status_t NOT NULL DEFAULT 'open',
  reviewed_by  uuid REFERENCES admin_users(id),
  reviewed_at  timestamptz,
  review_note  text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_flags_open ON message_flags(status, created_at DESC) WHERE status = 'open';
CREATE INDEX idx_flags_subject ON message_flags(subject_profile_id, created_at DESC);

-- Strike ledger. Drives the escalation ladder.
CREATE TABLE moderation_actions (
  id          uuid PRIMARY KEY DEFAULT uuid_v7(),
  profile_id  uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  flag_id     uuid REFERENCES message_flags(id),
  action      mod_action_t NOT NULL,
  strike_no   smallint NOT NULL,
  reason      text NOT NULL,
  issued_by   uuid REFERENCES admin_users(id),   -- null = automated
  expires_at  timestamptz,                       -- for mutes
  refund_issued boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_modact_profile ON moderation_actions(profile_id, created_at DESC);

-- Behavioural signals — abuse detection without reading any message
CREATE OR REPLACE VIEW v_abuse_signals AS
SELECT
  p.id AS profile_id,
  p.display_name,
  count(DISTINCT m.conversation_id)                       AS conversations_messaged,
  count(m.id)                                             AS messages_sent,
  count(DISTINCT b.blocker_profile_id)                    AS times_blocked,
  count(DISTINCT f.id) FILTER (WHERE f.status <> 'dismissed') AS open_flags
FROM profiles p
LEFT JOIN messages m ON m.sender_profile_id = p.id
     AND m.created_at > now() - interval '7 days'
LEFT JOIN blocks b   ON b.blocked_profile_id = p.id
     AND b.created_at > now() - interval '30 days'
LEFT JOIN message_flags f ON f.subject_profile_id = p.id
WHERE p.deleted_at IS NULL
GROUP BY p.id, p.display_name
-- Multiple recipients blocking the same sender is the highest-precision
-- abuse signal available. Surface it before any content review.
HAVING count(DISTINCT b.blocker_profile_id) >= 2
    OR count(DISTINCT f.id) FILTER (WHERE f.status <> 'dismissed') >= 2;

-- Every human read of private message content is audited.
-- Application must call this before rendering any flagged thread.
CREATE OR REPLACE FUNCTION log_moderation_read(
  p_admin uuid, p_conversation uuid, p_flag uuid, p_reason text
) RETURNS void LANGUAGE sql AS $$
  INSERT INTO audit_log(admin_user_id, action, entity_type, entity_id, reason)
  VALUES (p_admin, 'moderation.read_messages', 'conversation', p_conversation,
          coalesce(p_reason, 'flag:' || p_flag::text));
$$;

-- ============================================================
-- 9. SEED — moderation terms (starter set; expand with real reports)
-- ============================================================
INSERT INTO moderation_terms (term, lang, category, severity, is_regex) VALUES
  ('[0-9]{10}',                   'en','contact_leak',      1, true),
  ('(upi|gpay|phonepe|paytm)',    'en','money_request',     2, true),
  ('(whatsapp|insta(gram)?)\s*(me|id)?', 'en','external_platform', 1, true),
  ('(send|share).{0,12}(pic|photo|selfie).{0,12}(private|without)', 'en','sexual_solicitation', 3, true);
-- Add Marathi, Hindi, Telugu and roman-transliterated terms before launch.
-- Do not ship with an English-only list: it catches almost nothing here.
