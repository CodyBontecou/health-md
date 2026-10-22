/** The fake exposes D1 plus a read-only test inspection surface. */
export class TestD1 implements D1Database {
  constructor(migrations?: string[]);
  applyMigration(migration: string): void;
  readonly sqlite: {
    prepare(query: string): {
      get(...values: (string | number | null)[]): Record<string, unknown> | undefined;
      all(...values: (string | number | null)[]): Record<string, unknown>[];
    };
    exec(query: string): void;
    close(): void;
  };
  prepare: D1Database["prepare"];
  batch: D1Database["batch"];
  exec: D1Database["exec"];
  withSession: D1Database["withSession"];
  dump: D1Database["dump"];
}
