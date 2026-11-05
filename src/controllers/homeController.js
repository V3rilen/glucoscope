import { checkConnection } from '../models/db.js';

export function showHome(req, res) {
  res.render('pages/home', { title: 'Home' });
}

export async function showHealth(req, res) {
  const databaseOk = await checkConnection();
  res.status(databaseOk ? 200 : 503).json({ status: databaseOk ? 'ok' : 'unavailable' });
}
