INSERT INTO public.wine_region_types (id, code, name) VALUES
  ('30000000-0000-4000-8000-000000000001', 'country', 'Country'),
  ('30000000-0000-4000-8000-000000000002', 'state_or_province', 'State / Province'),
  ('30000000-0000-4000-8000-000000000003', 'wine_region', 'Wine Region'),
  ('30000000-0000-4000-8000-000000000004', 'subregion', 'Subregion'),
  ('30000000-0000-4000-8000-000000000005', 'district', 'District'),
  ('30000000-0000-4000-8000-000000000006', 'commune_or_municipality', 'Commune / Municipality'),
  ('30000000-0000-4000-8000-000000000007', 'appellation', 'Appellation'),
  ('30000000-0000-4000-8000-000000000008', 'sub_appellation', 'Sub-Appellation'),
  ('30000000-0000-4000-8000-000000000009', 'vineyard', 'Vineyard'),
  ('30000000-0000-4000-8000-000000000010', 'climat_or_lieu_dit', 'Climat / Lieu-Dit'),
  ('30000000-0000-4000-8000-000000000011', 'estate', 'Estate'),
  ('30000000-0000-4000-8000-000000000012', 'winery', 'Winery'),
  ('30000000-0000-4000-8000-000000000013', 'producer', 'Producer')
ON CONFLICT (id) DO UPDATE
SET code = EXCLUDED.code,
    name = EXCLUDED.name;
