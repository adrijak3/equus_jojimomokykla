ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS extra_fee_eur NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (extra_fee_eur >= 0);
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS extra_fee_paid BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS bookings_extra_fee_unpaid_idx ON public.bookings (user_id, slot_date) WHERE extra_fee_eur > 0 AND extra_fee_paid = false AND status IN ('active','completed');
