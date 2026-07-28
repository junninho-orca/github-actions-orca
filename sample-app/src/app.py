"""
Sample app for Orca shift-left demo.
"""

import hashlib
import sqlite3

from flask import Flask, request

app = Flask(__name__)


@app.route("/user")
def get_user():
    user_id = request.args.get("id", "")
    conn = sqlite3.connect("demo.db")
    cur = conn.cursor()
    cur.execute("SELECT name FROM users WHERE id = ?", (user_id,))
    row = cur.fetchone()
    conn.close()
    return {"name": row[0] if row else None}


@app.route("/hash")
def hash_value():
    value = request.args.get("value", "")
    return {"hash": hashlib.sha256(value.encode()).hexdigest()}


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=False)
