CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE public.users (
  id uuid NOT NULL,
  CONSTRAINT users_pk PRIMARY KEY (id)
);

CREATE TABLE public.passkey_credentials (
  id text NOT NULL,
  user_id uuid NOT NULL,
  public_key bytea NOT NULL,
  sign_count bigint NOT NULL,
  CONSTRAINT passkey_credentials_pk PRIMARY KEY (id),
  CONSTRAINT passkey_credentials_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE,
  CONSTRAINT sign_count_non_negative CHECK (sign_count >= 0)
);

CREATE INDEX passkey_credentials_user_id_idx ON public.passkey_credentials(user_id);

CREATE TABLE public.user_email (
  user_id uuid NOT NULL,
  email citext NOT NULL,
  CONSTRAINT user_email_pk PRIMARY KEY (user_id, email),
  CONSTRAINT user_email_email_key UNIQUE (email),
  CONSTRAINT user_email_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE
);
