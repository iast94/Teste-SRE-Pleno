const express = require("express");
const client = require("prom-client");

const app = express();
const PORT = process.env.PORT || 8080;

/**
 * =========================
 * Prometheus Metrics Setup
 * =========================
 */
client.collectDefaultMetrics();

const httpRequestCounter = new client.Counter({
  name: "http_requests_total",
  help: "Total number of HTTP requests",
  labelNames: ["method", "route", "status"]
});

const httpRequestErrors = new client.Counter({
  name: "http_requests_errors_total",
  help: "Total number of HTTP error responses",
  labelNames: ["route", "status"]
});

const httpRequestDuration = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "HTTP request latency",
  labelNames: ["method", "route"],
  buckets: [0.1, 0.3, 0.5, 1, 1.5, 2, 3, 5]
});

/**
 * =========================
 * Middleware to track metrics
 * =========================
 */
app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer({
    method: req.method,
    route: req.path
  });

  res.on("finish", () => {
    httpRequestCounter.inc({
      method: req.method,
      route: req.path,
      status: res.statusCode
    });

    if (res.statusCode >= 400) {
      httpRequestErrors.inc({
        route: req.path,
        status: res.statusCode
      });
    }

    end();
  });

  next();
});

/**
 * =========================
 * Application Endpoints
 * =========================
 */

// Health check (liveness)
app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok" });
});

// Readiness check
app.get("/ready", (req, res) => {
  res.status(200).json({ status: "ready" });
});

// Normal request
app.get("/api", (req, res) => {
  res.json({ message: "Hello from SRE Pleno App 🚀" });
});

// Simulate slow request
app.get("/slow", async (req, res) => {
  const delay = Math.floor(Math.random() * 2000) + 500;
  await new Promise((resolve) => setTimeout(resolve, delay));
  res.json({ message: `Slow response (${delay}ms)` });
});

// Simulate error
app.get("/error", (req, res) => {
  res.status(500).json({ error: "Simulated internal error" });
});

// Prometheus metrics endpoint
app.get("/metrics", async (req, res) => {
  res.set("Content-Type", client.register.contentType);
  res.end(await client.register.metrics());
});

/**
 * =========================
 * Server
 * =========================
 */
app.listen(PORT, () => {
  console.log(`🚀 App running on port ${PORT}`);
});