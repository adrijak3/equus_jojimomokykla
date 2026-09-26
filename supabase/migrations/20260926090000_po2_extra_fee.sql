ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS extra_fee_eur NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (extra_fee_eur >= 0);
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS extra_fee_paid BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS bookings_extra_fee_unpaid_idx ON public.bookings (user_id, slot_date) WHERE extra_fee_eur > 0 AND extra_fee_paid = false AND status IN ('active','completed');

CREATE OR REPLACE FUNCTION public.book_po2_with_subscription(
  _slot_date date,
  _slot_time time,
  _subscription_id uuid,
  _extra_fee_eur numeric DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_sub public.subscriptions%ROWTYPE;
  v_booking uuid;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF _extra_fee_eur < 0 THEN RAISE EXCEPTION 'INVALID_EXTRA_FEE'; END IF;

  SELECT * INTO v_sub FROM public.subscriptions
   WHERE id = _subscription_id AND user_id = v_user
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SUBSCRIPTION_NOT_FOUND'; END IF;
  IF NOT v_sub.paid THEN RAISE EXCEPTION 'SUBSCRIPTION_NOT_PAID'; END IF;
  IF v_sub.expires_at < _slot_date THEN RAISE EXCEPTION 'SUBSCRIPTION_EXPIRED'; END IF;
  IF v_sub.lessons_used >= v_sub.lessons_total THEN RAISE EXCEPTION 'NO_SUBSCRIPTION_LESSONS_LEFT'; END IF;
  IF v_sub.lesson_type NOT IN ('sportine', 'sportine_po2') THEN RAISE EXCEPTION 'SUBSCRIPTION_NOT_ELIGIBLE_FOR_PO2'; END IF;

  INSERT INTO public.bookings (
    user_id, slot_date, slot_time, status, subscription_id,
    counts_in_subscription, extra_fee_eur, extra_fee_paid
  ) VALUES (
    v_user, _slot_date, _slot_time, 'active', _subscription_id,
    true, _extra_fee_eur, false
  ) RETURNING id INTO v_booking;

  UPDATE public.subscriptions
     SET lessons_used = (
       SELECT count(*) FROM public.bookings b
        WHERE b.subscription_id = _subscription_id
          AND b.status <> 'cancelled'
          AND b.counts_in_subscription IS NOT FALSE
     )
   WHERE id = _subscription_id;

  RETURN jsonb_build_object('ok', true, 'booking_id', v_booking, 'subscription_id', _subscription_id, 'extra_fee_eur', _extra_fee_eur);
END;
$$;

GRANT EXECUTE ON FUNCTION public.book_po2_with_subscription(date, time, uuid, numeric) TO authenticated;
