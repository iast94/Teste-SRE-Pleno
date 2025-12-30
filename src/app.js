const express = require('express');
const client = require('prom-client');

const app = express();
const port = process.env.PORT || 8080;

// Configuração de métricas do Prometheus
const collectDefaultMetrics = client.collectDefaultMetrics;
collectDefaultMetrics();

const httpRequestCounter = new client.Counter({
  name: 'http_requests_total',
  help: 'Total de requisições HTTP',
  labelNames: ['method', 'route', 'status']
});

// Endpoint de Liveness (Tarefa 2)
app.get('/health', (req, res) => {
  res.status(200).send('OK');
});

// Endpoint de Readiness (Tarefa 2)
app.get('/ready', (req, res) => {
  res.status(200).send('Ready');
});

// Endpoint de Métricas (Tarefa 3)
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

app.get('/', (req, res) => {
  httpRequestCounter.inc({ method: 'GET', route: '/', status: 200 });
  res.send('SRE Pleno Test - App Running!');
});

app.listen(port, () => {
  console.log(`App ouvindo na porta ${port} em ambiente ${process.env.APP_ENV}`);
});