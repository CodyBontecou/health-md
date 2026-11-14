-- Exact replay identity is scoped to the receiving account. If concurrent
-- requests race, the failed metadata transaction's ciphertext is discarded.
DROP INDEX exports_user_plaintext_hash;
CREATE UNIQUE INDEX exports_user_plaintext_hash_unique ON exports(user_id, plaintext_sha256);
