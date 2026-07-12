-- Event timeline: response deadline + required answer publish time
ALTER TABLE public.event_revisions
  ADD COLUMN responses_due_at timestamptz;

UPDATE public.event_revisions
SET
  responses_due_at = ends_at
WHERE responses_due_at IS NULL;

UPDATE public.event_revisions
SET
  answers_published_at = GREATEST(ends_at, responses_due_at)
WHERE answers_published_at IS NULL;

ALTER TABLE public.event_revisions
  ALTER COLUMN responses_due_at SET NOT NULL,
  ALTER COLUMN answers_published_at SET NOT NULL;

ALTER TABLE public.event_revisions
  ADD CONSTRAINT event_revisions_starts_before_or_at_responses_due
    CHECK (starts_at <= responses_due_at),
  ADD CONSTRAINT event_revisions_responses_due_before_or_at_answers_published
    CHECK (responses_due_at <= answers_published_at);

-- Move scoring rules from event to question
DROP TABLE IF EXISTS public.event_region_score_rules;

CREATE TABLE public.event_question_region_score_rules (
  event_question_id uuid NOT NULL,
  wine_region_type_id uuid NOT NULL,
  points integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_question_region_score_rules_pk PRIMARY KEY (event_question_id, wine_region_type_id),
  CONSTRAINT event_question_region_score_rules_question_fk
    FOREIGN KEY (event_question_id) REFERENCES public.event_questions (id) ON DELETE RESTRICT,
  CONSTRAINT event_question_region_score_rules_wine_region_type_fk
    FOREIGN KEY (wine_region_type_id) REFERENCES public.wine_region_types (id) ON DELETE RESTRICT,
  CONSTRAINT event_question_region_score_rules_points_non_negative CHECK (points >= 0)
);

CREATE INDEX event_question_region_score_rules_wine_region_type_id_idx
  ON public.event_question_region_score_rules(wine_region_type_id);

CREATE TABLE public.event_question_score_component_rules (
  event_question_id uuid NOT NULL,
  component text NOT NULL,
  points integer NOT NULL,
  partial_points integer,
  alcohol_tolerance double precision,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_question_score_component_rules_pk PRIMARY KEY (event_question_id, component),
  CONSTRAINT event_question_score_component_rules_question_fk
    FOREIGN KEY (event_question_id) REFERENCES public.event_questions (id) ON DELETE RESTRICT,
  CONSTRAINT event_question_score_component_rules_component_valid
    CHECK (component IN ('variety', 'vintage', 'alcohol', 'producer', 'feature')),
  CONSTRAINT event_question_score_component_rules_points_non_negative CHECK (points >= 0),
  CONSTRAINT event_question_score_component_rules_partial_points_non_negative
    CHECK (partial_points IS NULL OR partial_points >= 0),
  CONSTRAINT event_question_score_component_rules_partial_lte_points
    CHECK (partial_points IS NULL OR partial_points <= points),
  CONSTRAINT event_question_score_component_rules_alcohol_tolerance_non_negative
    CHECK (alcohol_tolerance IS NULL OR alcohol_tolerance >= 0),
  CONSTRAINT event_question_score_component_rules_alcohol_tolerance_only_for_alcohol
    CHECK (alcohol_tolerance IS NULL OR component = 'alcohol')
);

-- Producer / feature fields on answers
ALTER TABLE public.event_question_correct_answer_revisions
  ADD COLUMN producer_wine_region_id uuid,
  ADD COLUMN feature text,
  ADD CONSTRAINT event_question_correct_answer_revisions_producer_wine_region_fk
    FOREIGN KEY (producer_wine_region_id) REFERENCES public.wine_regions (id) ON DELETE RESTRICT;

CREATE INDEX event_question_correct_answer_revisions_producer_wine_region_id_idx
  ON public.event_question_correct_answer_revisions(producer_wine_region_id);

ALTER TABLE public.event_question_response_revisions
  ADD COLUMN producer_wine_region_id uuid,
  ADD COLUMN feature text,
  ADD CONSTRAINT event_question_response_revisions_producer_wine_region_fk
    FOREIGN KEY (producer_wine_region_id) REFERENCES public.wine_regions (id) ON DELETE RESTRICT;

CREATE INDEX event_question_response_revisions_producer_wine_region_id_idx
  ON public.event_question_response_revisions(producer_wine_region_id);

-- Rating seasons
CREATE TABLE public.rating_seasons (
  id uuid NOT NULL,
  name text NOT NULL,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT rating_seasons_pk PRIMARY KEY (id),
  CONSTRAINT rating_seasons_name_not_blank CHECK (char_length(trim(name)) > 0),
  CONSTRAINT rating_seasons_starts_before_ends CHECK (ends_at IS NULL OR starts_at < ends_at)
);

CREATE UNIQUE INDEX rating_seasons_one_active_idx
  ON public.rating_seasons ((true))
  WHERE ends_at IS NULL;

CREATE TABLE public.user_season_ratings (
  user_id uuid NOT NULL,
  season_id uuid NOT NULL,
  rating integer NOT NULL DEFAULT 1000,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_season_ratings_pk PRIMARY KEY (user_id, season_id),
  CONSTRAINT user_season_ratings_user_fk
    FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE RESTRICT,
  CONSTRAINT user_season_ratings_season_fk
    FOREIGN KEY (season_id) REFERENCES public.rating_seasons (id) ON DELETE RESTRICT
);

CREATE INDEX user_season_ratings_season_rating_idx
  ON public.user_season_ratings(season_id, rating DESC, user_id);

CREATE TABLE public.user_rating_ledger (
  id uuid NOT NULL,
  user_id uuid NOT NULL,
  season_id uuid NOT NULL,
  event_question_id uuid NOT NULL,
  performance double precision NOT NULL,
  field_average double precision NOT NULL,
  delta integer NOT NULL,
  rating_after integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_rating_ledger_pk PRIMARY KEY (id),
  CONSTRAINT user_rating_ledger_user_fk
    FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE RESTRICT,
  CONSTRAINT user_rating_ledger_season_fk
    FOREIGN KEY (season_id) REFERENCES public.rating_seasons (id) ON DELETE RESTRICT,
  CONSTRAINT user_rating_ledger_question_fk
    FOREIGN KEY (event_question_id) REFERENCES public.event_questions (id) ON DELETE RESTRICT,
  CONSTRAINT user_rating_ledger_season_question_user_key UNIQUE (season_id, event_question_id, user_id),
  CONSTRAINT user_rating_ledger_performance_range CHECK (performance >= 0 AND performance <= 1),
  CONSTRAINT user_rating_ledger_field_average_range CHECK (field_average >= 0 AND field_average <= 1)
);

CREATE INDEX user_rating_ledger_user_season_created_idx
  ON public.user_rating_ledger(user_id, season_id, created_at DESC);

INSERT INTO public.rating_seasons (id, name, starts_at, ends_at, created_at)
VALUES (
  '01900000-0000-7000-8000-000000000001',
  'Season 1',
  TIMESTAMPTZ '2026-01-01 00:00:00+00',
  NULL,
  now()
);
