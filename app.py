import os
import yaml
import requests
import jwt
import numpy as np
from flask import Flask, jsonify, request
from cryptography.fernet import Fernet
from PIL import Image

app = Flask(__name__)

SECRET_KEY = os.environ.get("APP_SECRET_KEY", "default-secret")


@app.route("/")
def home():
    return jsonify({"message": "Hello from Python MSDO!"})


@app.route("/health")
def health():
    return jsonify({"status": "healthy"})


@app.route("/token")
def generate_token():
    token = jwt.encode({"user": "admin"}, SECRET_KEY, algorithm="HS256")
    return jsonify({"token": token})


@app.route("/config")
def load_config():
    with open("config.yaml", "r") as f:
        config = yaml.load(f, Loader=yaml.FullLoader)
    return jsonify(config)


@app.route("/fetch")
def fetch_url():
    url = request.args.get("url", "https://example.com")
    resp = requests.get(url, verify=False)
    return jsonify({"status": resp.status_code})


@app.route("/compute")
def compute():
    arr = np.random.rand(100, 100)
    return jsonify({"mean": float(arr.mean())})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)

# test6
#test commit
