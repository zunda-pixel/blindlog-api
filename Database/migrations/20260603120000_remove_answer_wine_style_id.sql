DROP INDEX IF EXISTS public.event_question_correct_answer_revisions_wine_style_id_idx;
DROP INDEX IF EXISTS public.event_question_response_revisions_wine_style_id_idx;

ALTER TABLE public.event_question_correct_answer_revisions
  DROP CONSTRAINT IF EXISTS event_question_correct_answer_revisions_wine_style_fk,
  DROP COLUMN IF EXISTS wine_style_id;

ALTER TABLE public.event_question_response_revisions
  DROP CONSTRAINT IF EXISTS event_question_response_revisions_wine_style_fk,
  DROP COLUMN IF EXISTS wine_style_id;
