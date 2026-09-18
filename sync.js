/**
 * Bata Kore Stock Movement — MySQL → Supabase sync
 *
 * Source : MySQL, host 192.1.1.38, database `reporting`, tables `dispatch` & `receiving`
 * Target : Supabase (Postgres) — run schema.sql there first
 *
 * Strategy: incremental sync using each row's `updatedAt` column as a
 * watermark. Every run, we pull only rows changed since the last successful
 * sync and upsert them into Supabase by `id` (same id as the MySQL source).
 * The watermark is stored locally in sync-state.json next to this script.
 *
 * Runs once immediately, then on a daily schedule (see SCHEDULE below).
 * Keep the terminal window open, same pattern as auto-sync.js.
 */

const mysql = require('mysql2/promise');
const { createClient } = require('@supabase/supabase-js');
const cron = require('node-cron');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

// ─── Config ─────────────────────────────────────────────────────
const STATE_FILE = path.join(__dirname, 'sync-state.json');
const TABLES = ['dispatch', 'receiving'];

// Cron schedule(s) to run the sync automatically each day.
// Default: 3 times a day. Edit these to fit when your source data actually changes.
const SCHEDULE = ['0 12 * * *', '0 18 * * *', '0 22 * * *']; // 12:00, 18:00, 22:00

// Column name mapping: MySQL camelCase -> Postgres snake_case
const COLUMN_MAP = {
  Id: 'id',
  bookedDate: 'booked_date',
  sendDate: 'send_date',
  documentDate: 'document_date',
  subCategory: 'sub_category',
  isFootware: 'is_footware',
  isFA2A: 'is_fa2a',
  createdAt: 'created_at',
  updatedAt: 'updated_at',
};

const PASSTHROUGH_COLUMNS = [
  'sender', 'receiver', 'invoice', 'article', 'size',
  'items', 'category', 'price', 'amount',
];

// ─── Clients ────────────────────────────────────────────────────
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY // service_role key — this script runs server-side only
);

async function getMysqlConnection() {
  return mysql.createConnection({
    host: process.env.MYSQL_HOST,
    user: process.env.MYSQL_USER,
    password: process.env.MYSQL_PASSWORD,
    database: process.env.MYSQL_DATABASE,
  });
}

// ─── State (last-synced watermark per table) ───────────────────
function loadState() {
  if (!fs.existsSync(STATE_FILE)) return {};
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
  } catch {
    return {};
  }
}

function saveState(state) {
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
}

// ─── Row transform: MySQL row -> Supabase row ──────────────────
function transformRow(row) {
  const out = {};
  for (const col of PASSTHROUGH_COLUMNS) {
    if (col in row) out[col] = row[col];
  }
  for (const [mysqlCol, pgCol] of Object.entries(COLUMN_MAP)) {
    if (mysqlCol in row) out[pgCol] = row[mysqlCol];
  }
  // MySQL tinyint(1) -> JS 0/1 -> Postgres boolean
  if ('is_footware' in out) out.is_footware = !!out.is_footware;
  if ('is_fa2a' in out) out.is_fa2a = !!out.is_fa2a;
  out.synced_at = new Date().toISOString();
  return out;
}

// ─── Sync one table ─────────────────────────────────────────────
async function syncTable(conn, table, since) {
  const [rows] = await conn.execute(
    `SELECT * FROM \`${table}\` WHERE updatedAt > ? ORDER BY updatedAt ASC LIMIT 5000`,
    [since]
  );

  if (rows.length === 0) {
    console.log(`[${table}] no changes since ${since}`);
    return since; // watermark unchanged
  }

  const payload = rows.map(transformRow);

  // Upsert in batches of 500 to stay well under request size limits
  const BATCH = 500;
  for (let i = 0; i < payload.length; i += BATCH) {
    const chunk = payload.slice(i, i + BATCH);
    const { error } = await supabase.from(table).upsert(chunk, { onConflict: 'id' });
    if (error) throw new Error(`[${table}] upsert failed: ${error.message}`);
  }

  const newWatermark = rows[rows.length - 1].updatedAt;
  console.log(`[${table}] synced ${rows.length} row(s), watermark -> ${newWatermark}`);
  return newWatermark;
}

// ─── Main run ────────────────────────────────────────────────────
async function runSync() {
  const startedAt = new Date().toISOString();
  console.log(`\n=== Sync started ${startedAt} ===`);

  const state = loadState();
  const conn = await getMysqlConnection();

  try {
    for (const table of TABLES) {
      // First run for a table: default to a wide-open backfill window.
      const since = state[table] || '1970-01-01 00:00:00';
      const newWatermark = await syncTable(conn, table, since);
      state[table] = newWatermark;
    }
    saveState(state);
    console.log('=== Sync finished OK ===\n');
  } catch (err) {
    console.error('=== Sync FAILED — state not advanced, will retry same window next run ===');
    console.error(err);
  } finally {
    await conn.end();
  }
}

// ─── Entry point ─────────────────────────────────────────────────
(async () => {
  await runSync(); // run once immediately on start

  for (const expr of SCHEDULE) {
    cron.schedule(expr, runSync);
  }
  console.log(`Scheduled sync at: ${SCHEDULE.join(', ')} (server local time). Leave this window open.`);
})();
