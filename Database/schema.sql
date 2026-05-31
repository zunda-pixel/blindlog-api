CREATE TABLE public.users (
  id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT users_pk PRIMARY KEY (id)
);

CREATE TABLE public.passkey_credentials (
  id text NOT NULL,
  user_id uuid NOT NULL,
  public_key bytea NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT passkey_credentials_pk PRIMARY KEY (id),
  CONSTRAINT passkey_credentials_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE RESTRICT
);

CREATE INDEX passkey_credentials_user_id_idx ON public.passkey_credentials(user_id);

CREATE TABLE public.passkey_credential_sign_counts (
  id uuid NOT NULL,
  passkey_credential_id text NOT NULL,
  sign_count bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT passkey_credential_sign_counts_pk PRIMARY KEY (id),
  CONSTRAINT passkey_credential_sign_counts_passkey_credential_fk FOREIGN KEY (passkey_credential_id) REFERENCES public.passkey_credentials (id) ON DELETE RESTRICT,
  CONSTRAINT passkey_credential_sign_counts_sign_count_non_negative CHECK (sign_count >= 0)
);

CREATE INDEX passkey_credential_sign_counts_latest_idx ON public.passkey_credential_sign_counts(passkey_credential_id, sign_count DESC, created_at DESC, id DESC);

CREATE TABLE public.user_email (
  user_id uuid NOT NULL,
  email citext NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_email_pk PRIMARY KEY (user_id, email),
  CONSTRAINT user_email_email_key UNIQUE (email),
  CONSTRAINT user_email_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE RESTRICT
);

CREATE TABLE public.images (
  id uuid NOT NULL,
  user_id uuid NOT NULL,
  cloudflare_image_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT images_pk PRIMARY KEY (id),
  CONSTRAINT images_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE RESTRICT,
  CONSTRAINT images_cloudflare_image_id_key UNIQUE (cloudflare_image_id)
);

CREATE INDEX images_user_id_idx ON public.images(user_id);

CREATE TABLE public.user_profiles (
  id uuid NOT NULL,
  user_id uuid NOT NULL,
  image_id uuid,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_profiles_pk PRIMARY KEY (id),
  CONSTRAINT user_profiles_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE RESTRICT,
  CONSTRAINT user_profiles_image_fk FOREIGN KEY (image_id) REFERENCES public.images (id) ON DELETE RESTRICT,
  CONSTRAINT user_profiles_name_length CHECK (char_length(trim(name)) BETWEEN 1 AND 100)
);

CREATE INDEX user_profiles_latest_idx ON public.user_profiles(user_id, created_at DESC, id DESC);

CREATE TABLE public.events (
  id uuid NOT NULL,
  organizer_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT events_pk PRIMARY KEY (id),
  CONSTRAINT events_organizer_user_fk FOREIGN KEY (organizer_user_id) REFERENCES public.users (id) ON DELETE RESTRICT
);

CREATE INDEX events_organizer_user_id_idx ON public.events(organizer_user_id);

CREATE TABLE public.event_revisions (
  id uuid NOT NULL,
  event_id uuid NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  image_id uuid,
  venue_name text NOT NULL,
  venue_address_line1 text NOT NULL,
  venue_address_line2 text,
  venue_locality text,
  venue_administrative_area text,
  venue_postal_code text,
  venue_country_code text NOT NULL,
  venue_latitude numeric(9,6),
  venue_longitude numeric(9,6),
  registration_starts_at timestamptz,
  registration_ends_at timestamptz,
  registration_period tstzrange GENERATED ALWAYS AS (
    CASE
      WHEN registration_starts_at IS NULL OR registration_ends_at IS NULL THEN NULL
      ELSE tstzrange(registration_starts_at, registration_ends_at, '[)')
    END
  ) STORED,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  event_period tstzrange GENERATED ALWAYS AS (tstzrange(starts_at, ends_at, '[)')) STORED,
  answers_published_at timestamptz,
  capacity integer,
  entry_fee_minor_amount integer,
  entry_fee_currency_code text,
  visibility text NOT NULL,
  published_at timestamptz,
  canceled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_revisions_pk PRIMARY KEY (id),
  CONSTRAINT event_revisions_event_fk FOREIGN KEY (event_id) REFERENCES public.events (id) ON DELETE RESTRICT,
  CONSTRAINT event_revisions_image_fk FOREIGN KEY (image_id) REFERENCES public.images (id) ON DELETE RESTRICT,
  CONSTRAINT event_revisions_title_not_blank CHECK (char_length(trim(title)) > 0),
  CONSTRAINT event_revisions_venue_name_not_blank CHECK (char_length(trim(venue_name)) > 0),
  CONSTRAINT event_revisions_venue_address_line1_not_blank CHECK (char_length(trim(venue_address_line1)) > 0),
  CONSTRAINT event_revisions_venue_country_code_length CHECK (char_length(venue_country_code) = 2),
  CONSTRAINT event_revisions_venue_latitude_range CHECK (venue_latitude IS NULL OR (venue_latitude >= -90 AND venue_latitude <= 90)),
  CONSTRAINT event_revisions_venue_longitude_range CHECK (venue_longitude IS NULL OR (venue_longitude >= -180 AND venue_longitude <= 180)),
  CONSTRAINT event_revisions_starts_before_ends CHECK (starts_at < ends_at),
  CONSTRAINT event_revisions_registration_starts_before_ends CHECK (registration_starts_at IS NULL OR registration_ends_at IS NULL OR registration_starts_at < registration_ends_at),
  CONSTRAINT event_revisions_capacity_positive CHECK (capacity IS NULL OR capacity > 0),
  CONSTRAINT event_revisions_entry_fee_minor_amount_non_negative CHECK (entry_fee_minor_amount IS NULL OR entry_fee_minor_amount >= 0),
  CONSTRAINT event_revisions_entry_fee_currency_code_length CHECK (entry_fee_currency_code IS NULL OR char_length(entry_fee_currency_code) = 3),
  CONSTRAINT event_revisions_visibility_valid CHECK (visibility IN ('public', 'unlisted', 'private'))
);

CREATE INDEX event_revisions_event_latest_idx ON public.event_revisions(event_id, created_at DESC, id DESC);
CREATE INDEX event_revisions_image_id_idx ON public.event_revisions(image_id);
CREATE INDEX event_revisions_visibility_starts_at_idx ON public.event_revisions(visibility, starts_at DESC, id DESC);
CREATE INDEX event_revisions_event_period_idx ON public.event_revisions USING gist(event_period);
CREATE INDEX event_revisions_registration_period_idx ON public.event_revisions USING gist(registration_period);

CREATE TABLE public.event_participants (
  id uuid NOT NULL,
  event_id uuid NOT NULL,
  user_id uuid NOT NULL,
  status text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_participants_pk PRIMARY KEY (id),
  CONSTRAINT event_participants_event_fk FOREIGN KEY (event_id) REFERENCES public.events (id) ON DELETE RESTRICT,
  CONSTRAINT event_participants_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE RESTRICT,
  CONSTRAINT event_participants_event_user_key UNIQUE (event_id, user_id),
  CONSTRAINT event_participants_status_valid CHECK (status IN ('registered', 'waitlisted', 'canceled', 'attended'))
);

CREATE INDEX event_participants_user_id_idx ON public.event_participants(user_id);
CREATE INDEX event_participants_event_status_idx ON public.event_participants(event_id, status);

CREATE TABLE public.event_questions (
  id uuid NOT NULL,
  event_id uuid NOT NULL,
  question_number integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_questions_pk PRIMARY KEY (id),
  CONSTRAINT event_questions_event_fk FOREIGN KEY (event_id) REFERENCES public.events (id) ON DELETE RESTRICT,
  CONSTRAINT event_questions_event_question_number_key UNIQUE (event_id, question_number),
  CONSTRAINT event_questions_question_number_positive CHECK (question_number > 0)
);

CREATE INDEX event_questions_event_id_idx ON public.event_questions(event_id);

CREATE TABLE public.event_question_revisions (
  id uuid NOT NULL,
  event_question_id uuid NOT NULL,
  image_id uuid,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_question_revisions_pk PRIMARY KEY (id),
  CONSTRAINT event_question_revisions_event_question_fk FOREIGN KEY (event_question_id) REFERENCES public.event_questions (id) ON DELETE RESTRICT,
  CONSTRAINT event_question_revisions_image_fk FOREIGN KEY (image_id) REFERENCES public.images (id) ON DELETE RESTRICT
);

CREATE INDEX event_question_revisions_event_question_latest_idx ON public.event_question_revisions(event_question_id, created_at DESC, id DESC);
CREATE INDEX event_question_revisions_image_id_idx ON public.event_question_revisions(image_id);

CREATE TABLE public.wine_styles (
  id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT wine_styles_pk PRIMARY KEY (id),
  CONSTRAINT wine_styles_code_key UNIQUE (code),
  CONSTRAINT wine_styles_name_key UNIQUE (name),
  CONSTRAINT wine_styles_code_not_blank CHECK (char_length(trim(code)) > 0),
  CONSTRAINT wine_styles_name_not_blank CHECK (char_length(trim(name)) > 0)
);

CREATE TABLE public.wine_varieties (
  id uuid NOT NULL,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT wine_varieties_pk PRIMARY KEY (id),
  CONSTRAINT wine_varieties_name_key UNIQUE (name),
  CONSTRAINT wine_varieties_name_not_blank CHECK (char_length(trim(name)) > 0)
);

CREATE TABLE public.wine_variety_styles (
  wine_variety_id uuid NOT NULL,
  wine_style_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT wine_variety_styles_pk PRIMARY KEY (wine_variety_id, wine_style_id),
  CONSTRAINT wine_variety_styles_wine_variety_fk FOREIGN KEY (wine_variety_id) REFERENCES public.wine_varieties (id) ON DELETE RESTRICT,
  CONSTRAINT wine_variety_styles_wine_style_fk FOREIGN KEY (wine_style_id) REFERENCES public.wine_styles (id) ON DELETE RESTRICT
);

CREATE INDEX wine_variety_styles_wine_style_id_idx ON public.wine_variety_styles(wine_style_id);

CREATE TABLE public.wine_region_types (
  id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT wine_region_types_pk PRIMARY KEY (id),
  CONSTRAINT wine_region_types_code_key UNIQUE (code),
  CONSTRAINT wine_region_types_name_key UNIQUE (name),
  CONSTRAINT wine_region_types_code_not_blank CHECK (char_length(trim(code)) > 0),
  CONSTRAINT wine_region_types_name_not_blank CHECK (char_length(trim(name)) > 0)
);

CREATE TABLE public.wine_regions (
  id uuid NOT NULL,
  parent_region_id uuid,
  wine_region_type_id uuid NOT NULL,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT wine_regions_pk PRIMARY KEY (id),
  CONSTRAINT wine_regions_parent_region_fk FOREIGN KEY (parent_region_id) REFERENCES public.wine_regions (id) ON DELETE RESTRICT,
  CONSTRAINT wine_regions_wine_region_type_fk FOREIGN KEY (wine_region_type_id) REFERENCES public.wine_region_types (id) ON DELETE RESTRICT,
  CONSTRAINT wine_regions_parent_name_key UNIQUE (parent_region_id, name),
  CONSTRAINT wine_regions_name_not_blank CHECK (char_length(trim(name)) > 0),
  CONSTRAINT wine_regions_not_own_parent CHECK (parent_region_id IS NULL OR parent_region_id <> id)
);

CREATE INDEX wine_regions_parent_region_id_idx ON public.wine_regions(parent_region_id);
CREATE INDEX wine_regions_wine_region_type_id_idx ON public.wine_regions(wine_region_type_id);
CREATE UNIQUE INDEX wine_regions_root_name_key ON public.wine_regions(name) WHERE parent_region_id IS NULL;

CREATE TABLE public.event_question_correct_answer_revisions (
  id uuid NOT NULL,
  event_question_id uuid NOT NULL,
  wine_style_id uuid,
  wine_region_id uuid,
  vintage integer,
  alcohol_by_volume numeric(5,2),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_question_correct_answer_revisions_pk PRIMARY KEY (id),
  CONSTRAINT event_question_correct_answer_revisions_event_question_fk FOREIGN KEY (event_question_id) REFERENCES public.event_questions (id) ON DELETE RESTRICT,
  CONSTRAINT event_question_correct_answer_revisions_wine_style_fk FOREIGN KEY (wine_style_id) REFERENCES public.wine_styles (id) ON DELETE RESTRICT,
  CONSTRAINT event_question_correct_answer_revisions_wine_region_fk FOREIGN KEY (wine_region_id) REFERENCES public.wine_regions (id) ON DELETE RESTRICT,
  CONSTRAINT event_question_correct_answer_revisions_vintage_positive CHECK (vintage IS NULL OR vintage > 0),
  CONSTRAINT event_question_correct_answer_revisions_alcohol_by_volume_range CHECK (alcohol_by_volume IS NULL OR (alcohol_by_volume >= 0 AND alcohol_by_volume <= 100))
);

CREATE INDEX event_question_correct_answer_revisions_event_question_latest_idx ON public.event_question_correct_answer_revisions(event_question_id, created_at DESC, id DESC);
CREATE INDEX event_question_correct_answer_revisions_wine_style_id_idx ON public.event_question_correct_answer_revisions(wine_style_id);
CREATE INDEX event_question_correct_answer_revisions_wine_region_id_idx ON public.event_question_correct_answer_revisions(wine_region_id);

CREATE TABLE public.event_question_correct_answer_revision_varieties (
  event_question_correct_answer_revision_id uuid NOT NULL,
  wine_variety_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_question_correct_answer_revision_varieties_pk PRIMARY KEY (event_question_correct_answer_revision_id, wine_variety_id),
  CONSTRAINT event_question_correct_answer_revision_varieties_answer_fk FOREIGN KEY (event_question_correct_answer_revision_id) REFERENCES public.event_question_correct_answer_revisions (id) ON DELETE RESTRICT,
  CONSTRAINT event_question_correct_answer_revision_varieties_wine_variety_fk FOREIGN KEY (wine_variety_id) REFERENCES public.wine_varieties (id) ON DELETE RESTRICT
);

CREATE INDEX event_question_correct_answer_revision_varieties_wine_variety_id_idx ON public.event_question_correct_answer_revision_varieties(wine_variety_id);

CREATE TABLE public.event_question_response_revisions (
  id uuid NOT NULL,
  event_question_id uuid NOT NULL,
  user_id uuid NOT NULL,
  wine_style_id uuid,
  wine_region_id uuid,
  vintage integer,
  alcohol_by_volume numeric(5,2),
  note text,
  submitted_at timestamptz NOT NULL,
  CONSTRAINT event_question_response_revisions_pk PRIMARY KEY (id),
  CONSTRAINT event_question_response_revisions_event_question_fk FOREIGN KEY (event_question_id) REFERENCES public.event_questions (id) ON DELETE RESTRICT,
  CONSTRAINT event_question_response_revisions_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE RESTRICT,
  CONSTRAINT event_question_response_revisions_wine_style_fk FOREIGN KEY (wine_style_id) REFERENCES public.wine_styles (id) ON DELETE RESTRICT,
  CONSTRAINT event_question_response_revisions_wine_region_fk FOREIGN KEY (wine_region_id) REFERENCES public.wine_regions (id) ON DELETE RESTRICT,
  CONSTRAINT event_question_response_revisions_vintage_positive CHECK (vintage IS NULL OR vintage > 0),
  CONSTRAINT event_question_response_revisions_alcohol_by_volume_range CHECK (alcohol_by_volume IS NULL OR (alcohol_by_volume >= 0 AND alcohol_by_volume <= 100))
);

CREATE INDEX event_question_response_revisions_event_question_user_latest_idx ON public.event_question_response_revisions(event_question_id, user_id, submitted_at DESC, id DESC);
CREATE INDEX event_question_response_revisions_user_id_idx ON public.event_question_response_revisions(user_id);
CREATE INDEX event_question_response_revisions_wine_style_id_idx ON public.event_question_response_revisions(wine_style_id);
CREATE INDEX event_question_response_revisions_wine_region_id_idx ON public.event_question_response_revisions(wine_region_id);

CREATE TABLE public.event_question_response_revision_varieties (
  event_question_response_revision_id uuid NOT NULL,
  wine_variety_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_question_response_revision_varieties_pk PRIMARY KEY (event_question_response_revision_id, wine_variety_id),
  CONSTRAINT event_question_response_revision_varieties_response_fk FOREIGN KEY (event_question_response_revision_id) REFERENCES public.event_question_response_revisions (id) ON DELETE RESTRICT,
  CONSTRAINT event_question_response_revision_varieties_wine_variety_fk FOREIGN KEY (wine_variety_id) REFERENCES public.wine_varieties (id) ON DELETE RESTRICT
);

CREATE INDEX event_question_response_revision_varieties_wine_variety_id_idx ON public.event_question_response_revision_varieties(wine_variety_id);

CREATE TABLE public.event_region_score_rules (
  event_id uuid NOT NULL,
  wine_region_type_id uuid NOT NULL,
  points integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_region_score_rules_pk PRIMARY KEY (event_id, wine_region_type_id),
  CONSTRAINT event_region_score_rules_event_fk FOREIGN KEY (event_id) REFERENCES public.events (id) ON DELETE RESTRICT,
  CONSTRAINT event_region_score_rules_wine_region_type_fk FOREIGN KEY (wine_region_type_id) REFERENCES public.wine_region_types (id) ON DELETE RESTRICT,
  CONSTRAINT event_region_score_rules_points_non_negative CHECK (points >= 0)
);

CREATE INDEX event_region_score_rules_wine_region_type_id_idx ON public.event_region_score_rules(wine_region_type_id);
