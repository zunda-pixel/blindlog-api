CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE IF NOT EXISTS public.users (
  id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT users_pk PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.passkey_credentials (
  id text NOT NULL,
  user_id uuid NOT NULL,
  public_key bytea NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT passkey_credentials_pk PRIMARY KEY (id),
  CONSTRAINT passkey_credentials_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS passkey_credentials_user_id_idx ON public.passkey_credentials(user_id);

CREATE TABLE IF NOT EXISTS public.passkey_credential_sign_counts (
  id uuid NOT NULL,
  passkey_credential_id text NOT NULL,
  sign_count bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT passkey_credential_sign_counts_pk PRIMARY KEY (id),
  CONSTRAINT passkey_credential_sign_counts_passkey_credential_fk FOREIGN KEY (passkey_credential_id) REFERENCES public.passkey_credentials (id) ON DELETE RESTRICT,
  CONSTRAINT passkey_credential_sign_counts_sign_count_non_negative CHECK (sign_count >= 0)
);

CREATE INDEX IF NOT EXISTS passkey_credential_sign_counts_latest_idx ON public.passkey_credential_sign_counts(passkey_credential_id, sign_count DESC, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS public.user_email (
  user_id uuid NOT NULL,
  email citext NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_email_pk PRIMARY KEY (user_id, email),
  CONSTRAINT user_email_email_key UNIQUE (email),
  CONSTRAINT user_email_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS public.images (
  id uuid NOT NULL,
  user_id uuid NOT NULL,
  cloudflare_image_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT images_pk PRIMARY KEY (id),
  CONSTRAINT images_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE RESTRICT,
  CONSTRAINT images_cloudflare_image_id_key UNIQUE (cloudflare_image_id)
);

CREATE INDEX IF NOT EXISTS images_user_id_idx ON public.images(user_id);

CREATE TABLE IF NOT EXISTS public.user_profiles (
  id uuid NOT NULL,
  user_id uuid NOT NULL,
  image_id uuid,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_profiles_pk PRIMARY KEY (id),
  CONSTRAINT user_profiles_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE RESTRICT,
  CONSTRAINT user_profiles_image_fk FOREIGN KEY (image_id) REFERENCES public.images (id) ON DELETE RESTRICT,
  CONSTRAINT user_profiles_name_length CHECK (char_length(trim(name)) BETWEEN 1 AND 100)
);

CREATE INDEX IF NOT EXISTS user_profiles_latest_idx ON public.user_profiles(user_id, created_at DESC, id DESC);
