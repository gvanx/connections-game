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
  label text NOT NULL,
  color text NOT NULL,
  weight int NOT NULL DEFAULT 10,
  text_color text NOT NULL DEFAULT '#ffffff',
  jackpot boolean NOT NULL DEFAULT false
);

-- 4. Seed the prizes
INSERT INTO prizes (label, color, weight, text_color, jackpot) VALUES
  ('5% off next purchase',  '#00b4d8', 30, '#ffffff', false),
  ('Free screen protector', '#ef476f', 25, '#ffffff', false),
  ('10% off next purchase', '#06d6a0', 25, '#ffffff', false),
  ('NAf 20 store credit',   '#7209b7', 20, '#ffffff', false),
  ('15% off next purchase', '#ff6b35', 20, '#ffffff', false),
  ('Free phone case',       '#118ab2', 15, '#ffffff', false),
  ('NAf 50 store credit',   '#f72585', 10, '#ffffff', false),
  ('Free JBL earbuds',      '#4361ee',  8, '#ffffff', false),
  ('Samsung Galaxy A07',    '#ffd60a',  2, '#1a1a2e', true);

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
CREATE OR REPLACE FUNCTION spin(code_text text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_code_id uuid;
  v_code    text;
  v_prize   record;
  v_total   int;
  v_rng     float;
  v_running float := 0;
BEGIN
  -- Lock the code row to prevent race conditions
  SELECT id, code INTO v_code_id, v_code
  FROM spin_codes
  WHERE code = upper(trim(code_text))
  FOR UPDATE;

  IF v_code_id IS NULL THEN
    RETURN jsonb_build_object('error', 'INVALID_CODE');
  END IF;

  -- Check if already used (after lock)
  IF (SELECT used FROM spin_codes WHERE id = v_code_id) THEN
    RETURN jsonb_build_object('error', 'ALREADY_USED');
  END IF;

  -- Pick weighted random prize
  SELECT sum(weight) INTO v_total FROM prizes;
  v_rng := random() * v_total;

  FOR v_prize IN SELECT * FROM prizes ORDER BY id LOOP
    v_running := v_running + v_prize.weight;
    IF v_rng <= v_running THEN
      EXIT;
    END IF;
  END LOOP;

  -- Mark code as used
  UPDATE spin_codes
  SET used = true, used_at = now()
  WHERE id = v_code_id;

  -- Log result
  INSERT INTO spin_results (code_id, prize)
  VALUES (v_code_id, v_prize.label);

  -- Return prize details
  RETURN jsonb_build_object(
    'label',      v_prize.label,
    'color',      v_prize.color,
    'text_color', v_prize.text_color,
    'jackpot',    v_prize.jackpot
  );
END;
$$;

-- 8. Grant execute to anon role
GRANT EXECUTE ON FUNCTION spin(text) TO anon;

-- 9. Revoke direct table manipulation policies that are no longer needed
-- (The RPC function runs as SECURITY DEFINER so it bypasses RLS)
-- Keep select on spin_codes only if needed for other purposes;
-- the spin() function handles everything now.
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
-- SELECT 'SPIN-' || upper(substr(md5(random()::text), 1, 4))
-- FROM generate_series(1, 50);
