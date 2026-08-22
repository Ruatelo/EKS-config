"""
Vulnerable Health Dashboard Application

INTENTIONALLY VULNERABLE — for security demonstration purposes only.
DO NOT deploy in production environments.

Vulnerability: Command injection via unsanitized user input in /check endpoint.
"""

from flask import Flask, request, render_template_string
import subprocess
import socket

app = Flask(__name__)

TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>System Health Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px;
                     border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        .status { color: #4CAF50; font-weight: bold; }
        input[type="text"] { padding: 8px; width: 300px; border: 1px solid #ddd; border-radius: 4px; }
        button { padding: 8px 20px; background: #2196F3; color: white; border: none;
                 border-radius: 4px; cursor: pointer; }
        button:hover { background: #1976D2; }
        pre { background: #263238; color: #EEFFFF; padding: 15px; border-radius: 4px;
              overflow-x: auto; white-space: pre-wrap; word-wrap: break-word; }
        .info { color: #666; font-size: 14px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>System Health Dashboard</h1>
        <p>Hostname: <strong>{{ hostname }}</strong></p>
        <p>Service Status: <span class="status">● Running</span></p>
        <hr>
        <h3>Network Connectivity Check</h3>
        <p class="info">Enter a hostname or IP to verify network reachability:</p>
        <form action="/check" method="GET">
            <input type="text" name="host" placeholder="e.g., google.com" value="{{ host }}">
            <button type="submit">Run Check</button>
        </form>
        {% if output %}
        <h3>Result:</h3>
        <pre>{{ output }}</pre>
        {% endif %}
    </div>
</body>
</html>
"""


@app.route("/")
def index():
    return render_template_string(
        TEMPLATE, hostname=socket.gethostname(), host="", output=""
    )


@app.route("/check")
def check():
    host = request.args.get("host", "")
    if not host:
        return render_template_string(
            TEMPLATE,
            hostname=socket.gethostname(),
            host=host,
            output="Please enter a hostname.",
        )

    # VULNERABILITY: Command injection — user input is passed directly to a shell command
    try:
        result = subprocess.run(
            f"ping -c 2 -W 2 {host}",
            shell=True,
            capture_output=True,
            text=True,
            timeout=15,
        )
        output = result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        output = "Command timed out."

    return render_template_string(
        TEMPLATE, hostname=socket.gethostname(), host=host, output=output
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
