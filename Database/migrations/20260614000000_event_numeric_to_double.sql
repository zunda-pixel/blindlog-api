ALTER TABLE public.event_revisions
  ALTER COLUMN venue_latitude TYPE double precision,
  ALTER COLUMN venue_longitude TYPE double precision;

ALTER TABLE public.event_question_correct_answer_revisions
  ALTER COLUMN alcohol_by_volume TYPE double precision;

ALTER TABLE public.event_question_response_revisions
  ALTER COLUMN alcohol_by_volume TYPE double precision;
