CREATE TABLE public.users (
  id uuid NOT NULL,
  CONSTRAINT users_pk PRIMARY KEY (id)
);

CREATE TABLE public.passkey_credentials (
  id varchar NOT NULL,
  user_id uuid NOT NULL references users(id),
  public_key bytea NOT NULL,
  sign_count bigint NOT NULL,
  CONSTRAINT passkey_credentials_pk PRIMARY KEY (id)
);

CREATE TABLE public.totps (
  password bytea NOT NULL,
  user_id uuid NOT NULL references users(id),
  email varchar NOT NULL
);

CREATE TABLE public.user_email (
  user_id uuid NOT NULL references users(id),
  email varchar NOT NULL,
  CONSTRAINT user_email_email_key UNIQUE (email)
);
