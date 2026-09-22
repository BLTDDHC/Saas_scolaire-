-- Accounts created with a generated initial password must change it after
-- their first successful authentication.  This is additive and preserves all
-- existing users.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT false;
