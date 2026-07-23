# Encrypted Mac query-context store

Health.md's Mac query-context store is an internal contract independent of the daily export schema. Store contract v1 persists `HealthMdCompactContextDay` records as one encrypted generation file per owner day. It does not change daily export schema v7 or any exported JSON, CSV, Markdown, or Obsidian field.

## Encryption and commits

A random 256-bit key is stored in the user's Keychain as a this-device-only, when-unlocked item. Every context-day blob and the complete manifest/index is independently authenticated with AES-256-GCM and domain-separated associated data. Owner dates, health values, and index entries are never written to plaintext files or filenames; generation filenames are random UUIDs.

An upsert writes a new immutable generation first, atomically replaces the encrypted manifest as the commit point, and removes the prior generation only after that commit. A crash can therefore leave an unreferenced encrypted blob, which garbage collection may remove, but cannot make an old manifest point at overwritten content. Files use owner-only permissions, and the store is excluded from backup.

Reads fail closed when the key is missing, authentication fails, a contract is unsupported, dates are duplicated or malformed, or a manifest entry does not match its blob. No partial record is returned.

## Traversal, deletion, and retention

The encrypted manifest lists owner-date identifiers in deterministic order. Callers can load a single day by identifier or use ordered traversal, which decrypts one day at a time. History is never represented as one aggregate encrypted JSON payload.

Deletion is explicit: callers can delete one owner day or all encrypted context. Full deletion remains available even when the key or ciphertext is damaged and removes the dedicated Keychain key after deleting the files for crypto-erasure. Mac Settings shows the exact day count/range and independently confirmed **Delete Older Context** and **Delete All Encrypted Context** actions. The former deletes only owner dates strictly before the chosen canonical boundary. Retention is never run implicitly and is independent from CLI requests, exported files, and Apple Health.

The store has no metric, day, history, byte-result, or result-count cap. Storage safety comes from independent daily blobs and streaming traversal, so old "tail" data never becomes inaccessible merely because newer history exists.
