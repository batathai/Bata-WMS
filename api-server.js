/**
 * Bata WMS — LAN-only live API for Dispatch / Receiving
 *
 * Reads directly from the source MySQL database (192.1.1.38 / `reporting`)
 * on every request — no sync delay, unlike the Supabase copy that sync.js
 * updates a few times a day.
 *
 * Serves both this API and the main app (Index/index.html — same Supabase
 * login/roles/dashboard as the public site) from one process, on plain
 * HTTP, so it only needs to be reachable from inside the office LAN. The
 * Dispatch/Receiving menus call this API for live data; every other menu
 * still talks to Supabase like the GitHub Pages copy does.
 *
 * Do NOT port-forward this to the internet — it has no auth of its own on
 * the API routes and talks to the production MySQL database.
 */

const path = require('path');
const express = require('express');
const mysql = require('mysql2/promise');
require('dotenv').config();

const PORT = process.env.API_PORT || 3001;
const TABLES = new Set(['dispatch', 'receiving']);

let pool;
function getPool() {
  if (!pool) {
    pool = mysql.createPool({
      host: process.env.MYSQL_HOST,
      user: process.env.MYSQL_USER,
      password: process.env.MYSQL_PASSWORD,
      database: process.env.MYSQL_DATABASE,
      waitForConnections: true,
      connectionLimit: 5,
    });
  }
  return pool;
}

// ─── Build a filtered, invoice-grouped query for dispatch/receiving ──────
// One row per invoice: Pair = sum(items) where isFootware, Accessories =
// sum(items) where not isFootware, ToTalAmount = sum(amount).
function buildQuery(table, filters) {
  const where = [];
  const params = [];

  if (filters.dateFrom) {
    where.push('documentDate >= ?');
    params.push(filters.dateFrom);
  }
  if (filters.dateTo) {
    where.push('documentDate <= ?');
    params.push(filters.dateTo);
  }
  if (filters.sender) {
    where.push('sender LIKE ?');
    params.push(`%${filters.sender}%`);
  }
  if (filters.receiver) {
    where.push('receiver LIKE ?');
    params.push(`%${filters.receiver}%`);
  }
  if (filters.invoice) {
    where.push('invoice LIKE ?');
    params.push(`%${filters.invoice}%`);
  }
  // "Warehouse" scope toggle from the mock-up — adjust this LIKE pattern if
  // your warehouse code prefix differs.
  if (filters.scope === 'warehouse') {
    where.push('(sender LIKE ? OR receiver LIKE ?)');
    params.push('%Warehouse%', '%Warehouse%');
  }

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const sql = `
    SELECT
      invoice,
      MIN(bookedDate)   AS bookedDate,
      MIN(documentDate) AS documentDate,
      MIN(sender)       AS sender,
      MIN(receiver)     AS receiver,
      SUM(CASE WHEN isFootware = 1 THEN items ELSE 0 END) AS pair,
      SUM(CASE WHEN isFootware = 0 THEN items ELSE 0 END) AS accessories,
      SUM(amount)       AS totalAmount
    FROM \`${table}\`
    ${whereSql}
    GROUP BY invoice
    ORDER BY MIN(documentDate) DESC, invoice DESC
    LIMIT ? OFFSET ?
  `;

  const page = Math.max(1, parseInt(filters.page, 10) || 1);
  const pageSize = Math.min(500, Math.max(1, parseInt(filters.pageSize, 10) || 100));
  params.push(pageSize, (page - 1) * pageSize);

  return { sql, params };
}

function buildCountQuery(table, filters) {
  const where = [];
  const params = [];

  if (filters.dateFrom) { where.push('documentDate >= ?'); params.push(filters.dateFrom); }
  if (filters.dateTo) { where.push('documentDate <= ?'); params.push(filters.dateTo); }
  if (filters.sender) { where.push('sender LIKE ?'); params.push(`%${filters.sender}%`); }
  if (filters.receiver) { where.push('receiver LIKE ?'); params.push(`%${filters.receiver}%`); }
  if (filters.invoice) { where.push('invoice LIKE ?'); params.push(`%${filters.invoice}%`); }
  if (filters.scope === 'warehouse') {
    where.push('(sender LIKE ? OR receiver LIKE ?)');
    params.push('%Warehouse%', '%Warehouse%');
  }

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const sql = `SELECT COUNT(DISTINCT invoice) AS total FROM \`${table}\` ${whereSql}`;
  return { sql, params };
}

const app = express();
app.use(express.static(path.join(__dirname, 'Index')));

app.get('/api/:table', async (req, res) => {
  const { table } = req.params;
  if (!TABLES.has(table)) {
    return res.status(404).json({ error: `Unknown table "${table}"` });
  }

  try {
    const conn = getPool();
    const { sql, params } = buildQuery(table, req.query);
    const { sql: countSql, params: countParams } = buildCountQuery(table, req.query);

    const [rows] = await conn.execute(sql, params);
    const [[{ total }]] = await conn.execute(countSql, countParams);

    res.json({ rows, total });
  } catch (err) {
    console.error(`[GET /api/${table}] failed:`, err);
    res.status(500).json({ error: 'Query failed — see server log' });
  }
});

app.listen(PORT, () => {
  console.log(`Bata WMS live API listening on http://localhost:${PORT}`);
  console.log('LAN-only: do not expose this port to the internet.');
});
