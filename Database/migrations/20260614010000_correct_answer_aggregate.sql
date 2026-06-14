-- Introduce a stable aggregate for a question's correct answer, mirroring the
-- events <-> event_revisions relationship. The append-only revisions table now
-- references the aggregate instead of the question directly, so the API can
-- return an `id` that stays unchanged across updates.

-- 1. Aggregate table: one stable correct-answer row per question.
CREATE TABLE public.event_question_correct_answers (
  id uuid NOT NULL,
  event_question_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_question_correct_answers_pk PRIMARY KEY (id),
  CONSTRAINT event_question_correct_answers_event_question_fk FOREIGN KEY (event_question_id) REFERENCES public.event_questions (id) ON DELETE RESTRICT,
  CONSTRAINT event_question_correct_answers_event_question_key UNIQUE (event_question_id)
);

-- 2. Backfill one aggregate per question. Use a fresh id and carry over the
--    oldest revision's created_at as the initial creation time.
INSERT INTO public.event_question_correct_answers (id, event_question_id, created_at)
SELECT DISTINCT ON (r.event_question_id)
  gen_random_uuid(), r.event_question_id, r.created_at
FROM public.event_question_correct_answer_revisions r
ORDER BY r.event_question_id, r.created_at ASC, r.id ASC;

-- 3. Link existing revisions to their aggregate.
ALTER TABLE public.event_question_correct_answer_revisions
  ADD COLUMN event_question_correct_answer_id uuid;

UPDATE public.event_question_correct_answer_revisions r
SET event_question_correct_answer_id = a.id
FROM public.event_question_correct_answers a
WHERE a.event_question_id = r.event_question_id;

ALTER TABLE public.event_question_correct_answer_revisions
  ALTER COLUMN event_question_correct_answer_id SET NOT NULL,
  ADD CONSTRAINT event_question_correct_answer_revisions_answer_fk FOREIGN KEY (event_question_correct_answer_id) REFERENCES public.event_question_correct_answers (id) ON DELETE RESTRICT;

-- 4. Drop the now-redundant direct link to event_questions.
DROP INDEX IF EXISTS public.event_question_correct_answer_revisions_event_question_latest_idx;

ALTER TABLE public.event_question_correct_answer_revisions
  DROP CONSTRAINT IF EXISTS event_question_correct_answer_revisions_event_question_fk,
  DROP COLUMN IF EXISTS event_question_id;

CREATE INDEX event_question_correct_answer_revisions_answer_latest_idx ON public.event_question_correct_answer_revisions(event_question_correct_answer_id, created_at DESC, id DESC);
