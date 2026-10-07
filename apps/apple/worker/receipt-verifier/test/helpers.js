import { readdirSync, readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";

const migrationDirectory = new URL("../migrations/", import.meta.url);

function rowObject(row) {
  return row === undefined ? null : { ...row };
}

/** A real SQLite database with the D1 statement methods used by the Worker. */
export function makeDB() {
  const raw = new DatabaseSync(":memory:");
  raw.exec("PRAGMA foreign_keys = ON");
  const migrations = readdirSync(migrationDirectory)
    .filter((name) => name.endsWith(".sql"))
    .sort();
  if (migrations.length === 0) {
    raw.close();
    throw new Error("No Worker migrations found");
  }
  try {
    for (const name of migrations) {
      raw.exec(readFileSync(new URL(name, migrationDirectory), "utf8"));
    }
  } catch (error) {
    raw.close();
    throw error;
  }

  function statement(sql, values = []) {
    function rows() {
      return raw.prepare(sql).all(...values).map(rowObject);
    }

    return {
      bind(...boundValues) {
        return statement(sql, boundValues);
      },
      async run() {
        const result = raw.prepare(sql).run(...values);
        return {
          success: true,
          meta: { changes: Number(result.changes), last_row_id: Number(result.lastInsertRowid) },
        };
      },
      async all() {
        return { results: rows(), success: true };
      },
      async first(column) {
        const row = rowObject(raw.prepare(sql).get(...values));
        return row === null ? null : column === undefined ? row : row[column];
      },
      _batch() {
        const results = rows();
        const meta = raw.prepare("SELECT changes() AS changes, last_insert_rowid() AS last_row_id").get();
        return { results, success: true, meta: { ...meta } };
      },
    };
  }

  return {
    raw,
    prepare(sql) {
      return statement(sql);
    },
    async batch(statements) {
      raw.exec("BEGIN IMMEDIATE");
      try {
        const results = statements.map((prepared) => prepared._batch());
        raw.exec("COMMIT");
        return results;
      } catch (error) {
        raw.exec("ROLLBACK");
        throw error;
      }
    },
  };
}

export function requestJSON(method, path, body) {
  return new Request(new URL(path, "https://worker.test"), {
    method,
    headers: { "Content-Type": "application/json" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

export function baseEnv(db) {
  return {
    DB: db,
    APNS_AUTH_KEY: "synthetic-key-never-signed",
    APNS_KEY_ID: "TEST_KEY",
    APNS_TEAM_ID: "TEST_TEAM",
    APNS_HOST: "api.push.apple.com",
  };
}

export function makeCtx() {
  const pending = [];
  return {
    waitUntil(promise) {
      pending.push(Promise.resolve(promise));
    },
    async drain() {
      while (pending.length > 0) {
        await Promise.all(pending.splice(0));
      }
    },
  };
}
