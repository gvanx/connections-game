# Supabase Queries

## Migration — Run these in SQL Editor (in order)

### Step 1: Create `prizes` table
```sql
CREATE TABLE prizes (
  id serial PRIMARY KEY,
  position integer NOT NULL UNIQUE,
  label text NOT NULL,
  weight integer NOT NULL DEFAULT 1,
  jackpot boolean NOT NULL DEFAULT false
);

INSERT INTO prizes (position, label, weight, jackpot) VALUES
  (0, '5% off next purchase',   30, false),
  (1, 'Free screen protector',  25, false),
  (2, '10% off next purchase',  25, false),
  (3, 'NAf 10 store credit',    20, false),
  (4, '15% off next purchase',  20, false),
  (5, 'Free phone case',        15, false),
  (6, 'NAf 25 store credit',    10, false),
  (7, 'Free earbuds',            8, false),
  (8, 'Samsung Galaxy A07',      2, true);
```

### Step 2: Create `spin_the_wheel` function
```sql
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
```

### Step 3: Grant execute to anon
```sql
GRANT EXECUTE ON FUNCTION spin_the_wheel(text) TO anon;
```

### Step 4: Test (use a test code)
```sql
SELECT spin_the_wheel('SPIN-TEST');
```

### Step 5: Drop old insecure RLS policies
Only run this after confirming Step 4 works.
```sql
DROP POLICY "anon_select_codes" ON spin_codes;
DROP POLICY "anon_update_codes" ON spin_codes;
DROP POLICY "anon_insert_results" ON spin_results;
```

---

## Operational Queries

### Active (unused) codes
```sql
SELECT code, created_at FROM spin_codes WHERE used = false ORDER BY created_at;
```

### Used codes + prizes won
```sql
SELECT sc.code, sr.prize, sr.spun_at
FROM spin_results sr
JOIN spin_codes sc ON sc.id = sr.code_id
ORDER BY sr.spun_at DESC;
```

### Generate more codes
Change `100` to however many you need.
```sql
INSERT INTO spin_codes (code)
SELECT 'SPIN-' || upper(substr(md5(i::text || random()::text), 1, 6))
FROM generate_series(1, 100) AS i
ON CONFLICT (code) DO NOTHING;
```

### Update prize weights
```sql
UPDATE prizes SET weight = 5 WHERE label = 'Free earbuds';
```

### View current prize config
```sql
SELECT position, label, weight, jackpot FROM prizes ORDER BY position;
```
