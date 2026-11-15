-- Bind one-time link consumption to the session created by the same D1
-- transaction. The nonce is random internal correlation state, never a browser
-- credential or public identifier.
ALTER TABLE magic_links ADD COLUMN claim_nonce TEXT;

CREATE UNIQUE INDEX magic_links_claim_nonce
  ON magic_links(claim_nonce)
  WHERE claim_nonce IS NOT NULL;
