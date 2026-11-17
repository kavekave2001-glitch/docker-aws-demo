from flask import Flask

app = Flask(__name__)

@app.route("/")
@app.route("/app2")
@app.route("/app2/")
def home():
    return "Hello from App2!"

@app.route("/health")
@app.route("/app2/health")
def health():
    return {"status": "healthy", "app": "app2"}

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)