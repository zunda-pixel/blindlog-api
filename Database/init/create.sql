CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE public.users (
  id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT users_pk PRIMARY KEY (id)
);

CREATE TABLE public.passkey_credentials (
  id text NOT NULL,
  user_id uuid NOT NULL,
  public_key bytea NOT NULL,
  sign_count bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT passkey_credentials_pk PRIMARY KEY (id),
  CONSTRAINT passkey_credentials_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE,
  CONSTRAINT sign_count_non_negative CHECK (sign_count >= 0)
);

CREATE INDEX passkey_credentials_user_id_idx ON public.passkey_credentials(user_id);

CREATE FUNCTION public.set_updated_at() RETURNS trigger
  LANGUAGE plpgsql AS
$$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER passkey_credentials_set_updated_at
  BEFORE UPDATE ON public.passkey_credentials
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.user_email (
  user_id uuid NOT NULL,
  email citext NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_email_pk PRIMARY KEY (user_id, email),
  CONSTRAINT user_email_email_key UNIQUE (email),
  CONSTRAINT user_email_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE
);

CREATE TABLE public.user_profiles (
  id uuid NOT NULL,
  user_id uuid NOT NULL,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_profiles_pk PRIMARY KEY (id),
  CONSTRAINT user_profiles_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE,
  CONSTRAINT user_profiles_name_length CHECK (char_length(trim(name)) BETWEEN 1 AND 100)
);

CREATE INDEX user_profiles_latest_idx ON public.user_profiles(user_id, created_at DESC, id DESC);

CREATE TABLE public.images (
  id uuid NOT NULL,
  user_id uuid NOT NULL,
  cloudflare_image_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT images_pk PRIMARY KEY (id),
  CONSTRAINT images_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE,
  CONSTRAINT images_cloudflare_image_id_key UNIQUE (cloudflare_image_id)
);

CREATE INDEX images_user_id_idx ON public.images(user_id);
