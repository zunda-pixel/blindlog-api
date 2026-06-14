-- Introduce a stable aggregate for a user's response to a question, mirroring
-- the events <-> event_revisions relationship (and the correct-answer fix). The
-- append-only revisions table now references the aggregate instead of carrying
-- (event_question_id, user_id) directly, so the API can return an `id` that
-- stays unchanged across updates.

-- 1. Aggregate table: one stable response row per (question, user).
CREATE TABLE public.event_question_responses (
  id uuid NOT NULL,
  event_question_id uuid NOT NULL,
  user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_question_responses_pk PRIMARY KEY (id),
  CONSTRAINT event_question_responses_event_question_fk FOREIGN KEY (event_question_id) REFERENCES public.event_questions (id) ON DELETE RESTRICT,
  CONSTRAINT event_question_responses_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE RESTRICT,
  CONSTRAINT event_question_responses_event_question_user_key UNIQUE (event_question_id, user_id)
);

CREATE INDEX event_question_responses_user_id_idx ON public.event_question_responses(user_id);

-- 2. Backfill one aggregate per (question, user). Use a fresh id and carry over
--    the oldest revision's submitted_at as the initial submission time.
INSERT INTO public.event_question_responses (id, event_question_id, user_id, created_at)
SELECT DISTINCT ON (r.event_question_id, r.user_id)
  gen_random_uuid(), r.event_question_id, r.user_id, r.submitted_at
FROM public.event_question_response_revisions r
ORDER BY r.event_question_id, r.user_id, r.submitted_at ASC, r.id ASC;

-- 3. Link existing revisions to their aggregate.
ALTER TABLE public.event_question_response_revisions
  ADD COLUMN event_question_response_id uuid;

UPDATE public.event_question_response_revisions r
SET event_question_response_id = a.id
FROM public.event_question_responses a
WHERE a.event_question_id = r.event_question_id
  AND a.user_id = r.user_id;

ALTER TABLE public.event_question_response_revisions
  ALTER COLUMN event_question_response_id SET NOT NULL,
  ADD CONSTRAINT event_question_response_revisions_response_fk FOREIGN KEY (event_question_response_id) REFERENCES public.event_question_responses (id) ON DELETE RESTRICT;

-- 4. Drop the now-redundant direct links to event_questions / users.
DROP INDEX IF EXISTS public.event_question_response_revisions_event_question_user_latest_idx;
DROP INDEX IF EXISTS public.event_question_response_revisions_user_id_idx;

ALTER TABLE public.event_question_response_revisions
  DROP CONSTRAINT IF EXISTS event_question_response_revisions_event_question_fk,
  DROP CONSTRAINT IF EXISTS event_question_response_revisions_user_fk,
  DROP COLUMN IF EXISTS event_question_id,
  DROP COLUMN IF EXISTS user_id;

CREATE INDEX event_question_response_revisions_response_latest_idx ON public.event_question_response_revisions(event_question_response_id, submitted_at DESC, id DESC);
