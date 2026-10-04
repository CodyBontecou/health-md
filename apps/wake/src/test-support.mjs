/** Fake D1 backed by in-memory SQLite. Node-only test boundary, no remote I/O. */
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";

export class TestD1 {
  sqlite = new DatabaseSync(":memory:");
  constructor(migrations = ["0001_init.sql"]) {
    for (const migration of migrations) this.applyMigration(migration);
  }
  applyMigration(migration) {
    this.sqlite.exec(readFileSync(new URL(`../migrations/${migration}`, import.meta.url), "utf8"));
  }
  prepare(query) { return new TestStatement(this, query); }
  async batch(statements) {
    this.sqlite.exec("BEGIN");
    try {
      const results = [];
      // Like D1, a batch cannot interleave its statements with another batch.
      for (const statement of statements) {
        if (!(statement instanceof TestStatement)) throw new Error("Foreign test statement");
        results.push(statement.execute());
      }
      this.sqlite.exec("COMMIT");
      return results;
    } catch (error) { this.sqlite.exec("ROLLBACK"); throw error; }
  }
  async exec(query) { this.sqlite.exec(query); return { count: 1, duration: 0 }; }
  withSession() {
    return { prepare: (query) => this.prepare(query), batch: (statements) => this.batch(statements), getBookmark: () => null };
  }
  async dump() { throw new Error("Not used by Worker tests"); }
}

class TestStatement {
  values = [];
  constructor(db, query) { this.db = db; this.query = query; }
  bind(...values) {
    this.values = values.map((value) => {
      if (value === null || typeof value === "string" || typeof value === "number") return value;
      throw new Error("Unsupported test binding");
    });
    return this;
  }
  async first(column) {
    const row = this.db.sqlite.prepare(this.query).get(...this.values);
    return row ? (column ? row[column] : row) : null;
  }
  async run() { return this.execute(); }
  execute() {
    const statement = this.db.sqlite.prepare(this.query);
    const isQuery = /^\s*(SELECT|PRAGMA)/i.test(this.query);
    const before = this.db.sqlite.prepare("SELECT total_changes() AS count").get().count;
    const result = isQuery ? { lastInsertRowid: 0 } : statement.run(...this.values);
    const after = this.db.sqlite.prepare("SELECT total_changes() AS count").get().count;
    // D1 metadata includes cascades; SQLite changes() in SQL counts the direct write.
    const changes = Number(after) - Number(before);
    return {
      success: true, results: isQuery ? statement.all(...this.values) : [],
      meta: {
        duration: 0, size_after: 0, rows_read: 0, rows_written: changes,
        last_row_id: Number(result.lastInsertRowid), changed_db: changes !== 0,
        changes,
      },
    };
  }
  async all() {
    return { ...(await this.run()), results: this.db.sqlite.prepare(this.query).all(...this.values) };
  }
  async raw(options) {
    const rows = this.db.sqlite.prepare(this.query).all(...this.values);
    const values = rows.map((row) => Object.values(row));
    return options?.columnNames ? [Object.keys(rows[0] ?? {}), ...values] : values;
  }
}
