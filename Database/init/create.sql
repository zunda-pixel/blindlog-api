CREATE TABLE public.users (
  id uuid DEFAULT uuidv7() NOT NULL,
  CONSTRAINT users_pk PRIMARY KEY (id)
);

CREATE TABLE public.user_email (
  user_id uuid NOT NULL,
  email varchar NOT NULL,
  CONSTRAINT user_email_unique UNIQUE (user_id)
);
