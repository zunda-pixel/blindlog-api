INSERT INTO public.rating_seasons (id, name, starts_at, ends_at, created_at)
VALUES (
  '01900000-0000-7000-8000-000000000001',
  'Season 1',
  TIMESTAMPTZ '2026-01-01 00:00:00+00',
  NULL,
  now()
)
ON CONFLICT (id) DO NOTHING;
