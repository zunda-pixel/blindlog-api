ALTER TABLE public.event_revisions
  ALTER COLUMN venue_latitude TYPE double precision,
  ALTER COLUMN venue_longitude TYPE double precision;

-- Re-create the range checks so their expressions normalize to double
-- precision; ALTER COLUMN TYPE leaves the existing constraint expressions
-- cast for the old numeric type.
ALTER TABLE public.event_revisions
  DROP CONSTRAINT event_revisions_venue_latitude_range,
  ADD CONSTRAINT event_revisions_venue_latitude_range CHECK (venue_latitude IS NULL OR (venue_latitude >= -90 AND venue_latitude <= 90)),
  DROP CONSTRAINT event_revisions_venue_longitude_range,
  ADD CONSTRAINT event_revisions_venue_longitude_range CHECK (venue_longitude IS NULL OR (venue_longitude >= -180 AND venue_longitude <= 180));

ALTER TABLE public.event_question_correct_answer_revisions
  ALTER COLUMN alcohol_by_volume TYPE double precision;

ALTER TABLE public.event_question_correct_answer_revisions
  DROP CONSTRAINT event_question_correct_answer_revisions_alcohol_by_volume_range,
  ADD CONSTRAINT event_question_correct_answer_revisions_alcohol_by_volume_range CHECK (alcohol_by_volume IS NULL OR (alcohol_by_volume >= 0 AND alcohol_by_volume <= 100));

ALTER TABLE public.event_question_response_revisions
  ALTER COLUMN alcohol_by_volume TYPE double precision;

ALTER TABLE public.event_question_response_revisions
  DROP CONSTRAINT event_question_response_revisions_alcohol_by_volume_range,
  ADD CONSTRAINT event_question_response_revisions_alcohol_by_volume_range CHECK (alcohol_by_volume IS NULL OR (alcohol_by_volume >= 0 AND alcohol_by_volume <= 100));
