CREATE TABLE public.users (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  CONSTRAINT users_pk PRIMARY KEY (id)
);

CREATE TABLE public.challenges (
  challenge bytea NOT null,
  expired_date timestamptz not null,
  CONSTRAINT challenges_unique PRIMARY KEY (challenge)
);

CREATE TABLE public.passkey_credentials (
  id varchar NOT null,
  public_key bytea not null,
  CONSTRAINT passkey_credentials_pk PRIMARY KEY (id)
);
