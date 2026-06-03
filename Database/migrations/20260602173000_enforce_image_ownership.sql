DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.user_profiles p
    JOIN public.images i ON i.id = p.image_id
    WHERE p.image_id IS NOT NULL
      AND i.user_id <> p.user_id
  ) THEN
    RAISE EXCEPTION 'user_profiles contains image references owned by another user';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.event_revisions r
    JOIN public.events e ON e.id = r.event_id
    JOIN public.images i ON i.id = r.image_id
    WHERE r.image_id IS NOT NULL
      AND i.user_id <> e.organizer_user_id
  ) THEN
    RAISE EXCEPTION 'event_revisions contains image references not owned by the organizer';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.event_question_revisions r
    JOIN public.event_questions q ON q.id = r.event_question_id
    JOIN public.events e ON e.id = q.event_id
    JOIN public.images i ON i.id = r.image_id
    WHERE r.image_id IS NOT NULL
      AND i.user_id <> e.organizer_user_id
  ) THEN
    RAISE EXCEPTION 'event_question_revisions contains image references not owned by the organizer';
  END IF;
END;
$$;

ALTER TABLE public.images
  ADD CONSTRAINT images_id_user_id_key UNIQUE (id, user_id);

ALTER TABLE public.user_profiles
  ADD CONSTRAINT user_profiles_image_owner_fk
  FOREIGN KEY (image_id, user_id)
  REFERENCES public.images (id, user_id)
  ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION public.enforce_event_revision_image_owner()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  image_owner_id uuid;
  organizer_user_id uuid;
BEGIN
  IF NEW.image_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT user_id INTO image_owner_id
  FROM public.images
  WHERE id = NEW.image_id;

  SELECT organizer_user_id INTO organizer_user_id
  FROM public.events
  WHERE id = NEW.event_id;

  IF image_owner_id IS NOT NULL
    AND organizer_user_id IS NOT NULL
    AND image_owner_id <> organizer_user_id THEN
    RAISE EXCEPTION 'event revision image must be owned by the event organizer'
      USING ERRCODE = '23503';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS event_revisions_image_owner_trg ON public.event_revisions;

CREATE TRIGGER event_revisions_image_owner_trg
BEFORE INSERT OR UPDATE OF event_id, image_id ON public.event_revisions
FOR EACH ROW
EXECUTE FUNCTION public.enforce_event_revision_image_owner();

CREATE OR REPLACE FUNCTION public.enforce_event_question_revision_image_owner()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  image_owner_id uuid;
  organizer_user_id uuid;
BEGIN
  IF NEW.image_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT user_id INTO image_owner_id
  FROM public.images
  WHERE id = NEW.image_id;

  SELECT e.organizer_user_id INTO organizer_user_id
  FROM public.event_questions q
  JOIN public.events e ON e.id = q.event_id
  WHERE q.id = NEW.event_question_id;

  IF image_owner_id IS NOT NULL
    AND organizer_user_id IS NOT NULL
    AND image_owner_id <> organizer_user_id THEN
    RAISE EXCEPTION 'event question revision image must be owned by the event organizer'
      USING ERRCODE = '23503';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS event_question_revisions_image_owner_trg ON public.event_question_revisions;

CREATE TRIGGER event_question_revisions_image_owner_trg
BEFORE INSERT OR UPDATE OF event_question_id, image_id ON public.event_question_revisions
FOR EACH ROW
EXECUTE FUNCTION public.enforce_event_question_revision_image_owner();
