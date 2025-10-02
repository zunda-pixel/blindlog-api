CREATE TABLE public.users (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  CONSTRAINT users_pk PRIMARY KEY (id)
);

CREATE TABLE public.passkey_credentials (
  id varchar NOT null,
  user_id uuid NOT null references users(id),
  public_key bytea not null,
  sign_count bigint not null,
  CONSTRAINT passkey_credentials_pk PRIMARY KEY (id)
);

CREATE TABLE public.totps (
  password bytea not null,
  userID uuid NOT null references users(id),
  email varchar not null
);
