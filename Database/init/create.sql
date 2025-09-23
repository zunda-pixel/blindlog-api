CREATE TABLE public.users (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  CONSTRAINT users_pk PRIMARY KEY (id)
);

CREATE TABLE public.challenges (
  challenge bytea NOT null,
  expired_date timestamptz not null,
  user_id uuid references users(id),
  purpose text NOT null,
  CONSTRAINT challenges_unique PRIMARY KEY (challenge)
);

CREATE TABLE public.passkey_credentials (
  id varchar NOT null,
  user_id uuid NOT null references users(id),
  public_key bytea not null,
  sign_count bigint not null,
  CONSTRAINT passkey_credentials_pk PRIMARY KEY (id)
);
