import pg from "pg";

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });

// Without a listener, an error on an idle client would crash the process.
pool.on("error", (err) => {
  console.error("Unexpected database pool error", err);
});

// Always pass values through $1-style placeholders, never string concatenation.
export function query(text, params) {
  return pool.query(text, params);
}

export async function checkConnection() {
  try {
    await pool.query("SELECT 1");
    return true;
  } catch (err) {
    console.error("Database connection check failed:", err.message);
    return false;
  }
}
