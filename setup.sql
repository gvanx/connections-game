-- ============================================================
-- CONNECTIONS CURACAO — SPIN & WIN
-- Run this SQL in Supabase SQL Editor:
-- https://supabase.com/dashboard/project/ngzxrygvotftmpgmzmcy/sql
-- ============================================================

-- 1. Create the spin_codes table (if not already created)
CREATE TABLE IF NOT EXISTS spin_codes (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  code text UNIQUE NOT NULL,
  created_at timestamptz DEFAULT now(),
  used boolean DEFAULT false,
  used_at timestamptz
);

-- 2. Create the spin_results table (if not already created)
CREATE TABLE IF NOT EXISTS spin_results (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  code_id uuid REFERENCES spin_codes(id),
  prize text NOT NULL,
  spun_at timestamptz DEFAULT now()
);

-- 3. Create the prizes config table
CREATE TABLE IF NOT EXISTS prizes (
  id serial PRIMARY KEY,
  position integer NOT NULL UNIQUE,
  label text NOT NULL,
  weight integer NOT NULL DEFAULT 1,
  jackpot boolean NOT NULL DEFAULT false
);

-- 4. Seed the prizes
INSERT INTO prizes (position, label, weight, jackpot) VALUES
  (0, '5% off this purchase',   30, false),
  (1, 'Free screen protector',  25, false),
  (2, '10% off this purchase',  25, false),
  (3, 'NAf 20 store credit',    20, false),
  (4, '15% off this purchase',  20, false),
  (5, 'Free phone case',        15, false),
  (6, 'NAf 50 store credit',    10, false),
  (7, 'Free JBL earbuds',        2, false),
  (8, 'Samsung A16',             1, true)
ON CONFLICT (position) DO NOTHING;

-- 5. Enable RLS
ALTER TABLE spin_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE spin_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE prizes ENABLE ROW LEVEL SECURITY;

-- 6. Allow anonymous read on prizes (for wheel drawing)
CREATE POLICY "anon_select_prizes" ON prizes
  FOR SELECT TO anon USING (true);

-- 7. RPC function: atomic spin
--    - Validates code
--    - Picks weighted-random prize
--    - Marks code used
--    - Logs result
--    - All in one transaction with row-level locking
CREATE OR REPLACE FUNCTION spin_the_wheel(p_code text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_code_row spin_codes%ROWTYPE;
  v_prize    prizes%ROWTYPE;
  v_total    integer;
  v_rng      double precision;
BEGIN
  -- Validate and lock the code
  SELECT * INTO v_code_row
  FROM spin_codes
  WHERE code = upper(trim(p_code)) AND used = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_CODE';
  END IF;

  -- Mark code as used
  UPDATE spin_codes
  SET used = true, used_at = now()
  WHERE id = v_code_row.id;

  -- Weighted random prize selection
  SELECT sum(weight) INTO v_total FROM prizes;
  v_rng := random() * v_total;

  SELECT * INTO v_prize
  FROM (
    SELECT *, sum(weight) OVER (ORDER BY position) AS cumulative
    FROM prizes
  ) sub
  WHERE cumulative >= v_rng
  ORDER BY position
  LIMIT 1;

  -- Log result
  INSERT INTO spin_results (code_id, prize)
  VALUES (v_code_row.id, v_prize.label);

  -- Return result
  RETURN json_build_object(
    'prize_index', v_prize.position,
    'prize_label', v_prize.label,
    'jackpot',     v_prize.jackpot,
    'code',        v_code_row.code
  );
END;
$$;

-- 8. Grant execute to anon role
GRANT EXECUTE ON FUNCTION spin_the_wheel(text) TO anon;

-- 9. Revoke direct table manipulation policies that are no longer needed
-- (The RPC function runs as SECURITY DEFINER so it bypasses RLS)
DROP POLICY IF EXISTS "anon_update_codes" ON spin_codes;
DROP POLICY IF EXISTS "anon_insert_results" ON spin_results;
DROP POLICY IF EXISTS "anon_select_codes" ON spin_codes;

-- 10. Insert test codes (if not already present)
INSERT INTO spin_codes (code) VALUES
  ('SPIN-TEST'),
  ('SPIN-DEMO'),
  ('SPIN-WIN1')
ON CONFLICT (code) DO NOTHING;

-- 11. Generate batch codes (run when you need more)
-- INSERT INTO spin_codes (code)
-- SELECT 'SPIN-' || upper(substr(md5(i::text || random()::text), 1, 6))
-- FROM generate_series(1, 100) AS i
-- ON CONFLICT (code) DO NOTHING;
