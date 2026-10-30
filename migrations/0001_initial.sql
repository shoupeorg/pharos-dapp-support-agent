CREATE TABLE IF NOT EXISTS reports (id TEXT PRIMARY KEY, tx_hash TEXT NOT NULL, outcome TEXT NOT NULL, confidence TEXT NOT NULL, source TEXT NOT NULL, report_json TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS reports_created_at ON reports(created_at DESC);
CREATE INDEX IF NOT EXISTS reports_tx_hash ON reports(tx_hash);