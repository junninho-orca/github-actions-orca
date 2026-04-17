"""
Sample app for Orca shift-left demo. Intentionally contains issues so the
CI scan produces findings. Do NOT use as a reference implementation.

Planted issues:
  - Hardcoded secret (secrets scan)
  - SQL injection via string concatenation (SAST)
  - Weak hash (MD5) for password-ish value (SAST)
  - Debug mode + binding to 0.0.0.0 (SAST / IaC-ish)
"""

import hashlib
import sqlite3

from flask import Flask, request

app = Flask(__name__)

# Secrets finding: hardcoded AWS-looking key.
AWS_ACCESS_KEY_ID = "AKIAI3X7MZPQ2RS4TUVW"
AWS_SECRET_ACCESS_KEY = "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"


@app.route("/user")
def get_user():
    # SAST finding: SQL injection via string concatenation.
    user_id = request.args.get("id", "")
    conn = sqlite3.connect("demo.db")
    cur = conn.cursor()
    cur.execute("SELECT name FROM users WHERE id = '" + user_id + "'")
    row = cur.fetchone()
    conn.close()
    return {"name": row[0] if row else None}


@app.route("/hash")
def weak_hash():
    # SAST finding: MD5 for anything credential-like.
    value = request.args.get("value", "")
    return {"hash": hashlib.md5(value.encode()).hexdigest()}


if __name__ == "__main__":
    # SAST / misconfig: debug=True in a bound-to-all listener.
    app.run(host="0.0.0.0", port=5000, debug=True)
