from flask import Flask

app = Flask(__name__)

@app.route("/")
@app.route("/app1")
@app.route("/app1/")
def home():
    return "Hello from App1!"

@app.route("/health")
@app.route("/app1/health")
def health():
    return {"status": "healthy", "app": "app1"}

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)