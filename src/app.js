const express = require('express');
const client = require('prom-client');

const app = express();
const PORT = process.env.PORT || 8080;

/**
 * =========================
 * Prometheus setup
 * =========================
 */
const register = new client.Registry();

// Métricas padrão (CPU, memória, event loop etc.)
client.collectDefaultMetrics({ register });

// Contador de requests HTTP
const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status'],
});

// Histograma de latência
const httpRequestDurationSeconds = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request latency in seconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.05, 0.1, 0.2, 0.5, 1, 2, 5],
});

register.registerMetric(httpRequestsTotal);
register.registerMetric(httpRequestDurationSeconds);

/**
 * =========================
 * Middleware de métricas
 * =========================
 */
app.use((req, res, next) => {
  const start = process.hrtime();

  res.on('finish', () => {
    const diff = process.hrtime(start);
    const durationMs = (diff[0] * 1e3 + diff[1] / 1e6).toFixed(2);
    const route = req.route?.path || req.path;
    const timestamp = new Date().toISOString();
    const level = res.statusCode >= 500 ? 'ERROR' : 'INFO';

    // Este log abaixo bate exatamente com o seu filtro Grok do Logstash:
    // %{TIMESTAMP_ISO8601:timestamp} %{LOGLEVEL:level} %{URIPATHPARAM:endpoint} latency=%{NUMBER:latency:float}ms
    console.log(`${timestamp} ${level} ${route} latency=${durationMs}ms`);

    // Mantém as métricas do Prometheus
    httpRequestsTotal.labels(req.method, route, res.statusCode.toString()).inc();
    httpRequestDurationSeconds.labels(req.method, route, res.statusCode.toString()).observe(durationMs / 1000);
  });

  next();
});

/**
 * =========================
 * Rotas de sucesso (2xx)
 * =========================
 */

// Root
app.get('/', (req, res) => {
  res.json({ message: 'OK' });
});

// Healthcheck
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

/**
 * =========================
 * Redirecionamento real (3xx)
 * =========================
 */
app.get('/redirect', (req, res) => {
  res.redirect(302, '/');
});

/**
 * =========================
 * Erros reais do CLIENTE (4xx)
 * =========================
 */

// Contrato inválido (parâmetro obrigatório)
app.get('/user', (req, res) => {
  if (!req.query.id) {
    return res.status(400).json({
      error: 'Missing required query parameter: id',
    });
  }

  res.json({ userId: req.query.id });
});

/**
 * =========================
 * Erros reais do SERVIDOR (5xx)
 * =========================
 */

// Bug interno (exceção não tratada)
app.get('/process', (req, res) => {
  throw new Error('Unexpected internal processing error');
});

// Simula dependência lenta / timeout
app.get('/dependency', async (req, res) => {
  await new Promise(resolve => setTimeout(resolve, 3000));
  throw new Error('Upstream dependency timeout');
});

// Latência alta, mas sucesso
app.get('/slow', async (req, res) => {
  await new Promise(resolve => setTimeout(resolve, 1500));
  res.json({ message: 'Slow but successful response' });
});

/**
 * =========================
 * Handler global de erro (5xx)
 * =========================
 */
app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'Internal Server Error' });
});

/**
 * =========================
 * Endpoint de métricas
 * =========================
 */
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

/**
 * =========================
 * Start server
 * =========================
 */
app.listen(PORT, () => {
  console.log(`App running on port ${PORT}`);
});