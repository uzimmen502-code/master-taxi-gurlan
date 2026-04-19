// Master Taxi Gurlan — Backend Server
const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const { Pool } = require('pg');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });
app.use(express.json());

const db = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgresql://postgres:mORgvAXSfEcAHFHeasglhTFnTIhWFJsN@postgres.railway.internal:5432/railway',
  ssl: { rejectUnauthorized: false },
});

const wsClients = new Map();

wss.on('connection', (ws, req) => {
  const params = new URLSearchParams(req.url.replace('/?',''));
  const type = params.get('type');
  const id = params.get('id');
  if (id) wsClients.set(id, ws);

  ws.on('message', async (msg) => {
    const data = JSON.parse(msg);
    if (data.type === 'location_update' && type === 'driver') {
      await db.query('UPDATE drivers SET lat=$1, lng=$2, last_seen=NOW() WHERE id=$3', [data.lat, data.lng, id]);
    }
    if (data.type === 'accept_order' && type === 'driver') {
      await handleAcceptOrder(data.order_id, id);
    }
  });

  ws.on('close', () => {
    wsClients.delete(id);
    if (type === 'driver') db.query('UPDATE drivers SET is_active=FALSE WHERE id=$1', [id]);
  });
});

function haversine(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = (lat2-lat1)*Math.PI/180;
  const dLng = (lng2-lng1)*Math.PI/180;
  const a = Math.sin(dLat/2)**2 + Math.cos(lat1*Math.PI/180)*Math.cos(lat2*Math.PI/180)*Math.sin(dLng/2)**2;
  return R*2*Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
}

const RADIUS_STEPS = [2, 5, 10];
const WAIT_SECONDS = 15;

async function broadcastOrder(orderId) {
  const { rows } = await db.query('SELECT * FROM orders WHERE id=$1', [orderId]);
  const order = rows[0];
  if (!order || order.status !== 'pending') return;
  await db.query("UPDATE orders SET status='broadcasting' WHERE id=$1", [orderId]);
  for (const radius of RADIUS_STEPS) {
    const accepted = await broadcastToRadius(order, radius);
    if (accepted) return;
    await new Promise(r => setTimeout(r, WAIT_SECONDS*1000));
    const check = await db.query('SELECT status FROM orders WHERE id=$1', [orderId]);
    if (check.rows[0]?.status !== 'broadcasting') return;
  }
  await db.query("UPDATE orders SET status='cancelled' WHERE id=$1", [orderId]);
  const userWs = wsClients.get(order.user_id);
  if (userWs?.readyState === WebSocket.OPEN)
    userWs.send(JSON.stringify({ type: 'no_driver', order_id: orderId }));
}

async function broadcastToRadius(order, radius) {
  const { rows } = await db.query(
    `SELECT id, lat, lng FROM drivers WHERE is_active=TRUE AND id NOT IN (SELECT driver_id FROM broadcasts WHERE order_id=$1)`,
    [order.id]
  );
  const nearby = rows.filter(d => haversine(order.from_lat, order.from_lng, d.lat, d.lng) <= radius);
  if (!nearby.length) return false;
  for (const driver of nearby) {
    await db.query(
      `INSERT INTO broadcasts (order_id, driver_id, radius_km, expires_at) VALUES ($1,$2,$3,NOW()+INTERVAL '15 seconds')`,
      [order.id, driver.id, radius]
    );
    const driverWs = wsClients.get(driver.id);
    if (driverWs?.readyState === WebSocket.OPEN)
      driverWs.send(JSON.stringify({
        type: 'new_order', order_id: order.id,
        from_address: order.from_address, to_address: order.to_address,
        from_lat: order.from_lat, from_lng: order.from_lng,
        to_lat: order.to_lat, to_lng: order.to_lng,
        distance_km: haversine(order.from_lat, order.from_lng, order.to_lat, order.to_lng).toFixed(1),
        user_phone: order.user_phone,
        expires_at: Date.now() + WAIT_SECONDS*1000,
      }));
  }
  await new Promise(r => setTimeout(r, WAIT_SECONDS*1000));
  const check = await db.query('SELECT status FROM orders WHERE id=$1', [order.id]);
  return check.rows[0]?.status === 'accepted';
}

async function handleAcceptOrder(orderId, driverId) {
  const result = await db.query(
    `UPDATE orders SET status='accepted', driver_id=$1, accepted_at=NOW() WHERE id=$2 AND status='broadcasting' RETURNING *`,
    [driverId, orderId]
  );
  if (!result.rows.length) {
    const ws = wsClients.get(driverId);
    if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'order_taken', order_id: orderId }));
    return;
  }
  const order = result.rows[0];
  await db.query("UPDATE broadcasts SET status='accepted' WHERE order_id=$1 AND driver_id=$2", [orderId, driverId]);
  await db.query("UPDATE broadcasts SET status='expired' WHERE order_id=$1 AND driver_id!=$2", [orderId, driverId]);
  const driverWs = wsClients.get(driverId);
  if (driverWs?.readyState === WebSocket.OPEN) driverWs.send(JSON.stringify({ type: 'order_confirmed', order }));
  const userWs = wsClients.get(order.user_id);
  if (userWs?.readyState === WebSocket.OPEN) {
    const dr = await db.query('SELECT name, car_model, car_number FROM drivers WHERE id=$1', [driverId]);
    userWs.send(JSON.stringify({ type: 'driver_found', driver: dr.rows[0], order_id: orderId }));
  }
}

app.post('/api/orders', async (req, res) => {
  const { user_id, from_lat, from_lng, from_address, to_lat, to_lng, to_address } = req.body;
  try {
    const result = await db.query(
      `INSERT INTO orders (user_id,from_lat,from_lng,from_address,to_lat,to_lng,to_address) VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
      [user_id, from_lat, from_lng, from_address, to_lat, to_lng, to_address]
    );
    const order = result.rows[0];
    await db.query(
      `INSERT INTO frequent_addresses (user_id,address,lat,lng) VALUES ($1,$2,$3,$4) ON CONFLICT (user_id,address) DO UPDATE SET count=frequent_addresses.count+1, last_used=NOW()`,
      [user_id, to_address, to_lat, to_lng]
    );
    res.json({ success: true, order });
    broadcastOrder(order.id);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/users/register', async (req, res) => {
  const { phone, name } = req.body;
  try {
    const result = await db.query(
      `INSERT INTO users (phone,name) VALUES ($1,$2) ON CONFLICT (phone) DO UPDATE SET name=EXCLUDED.name RETURNING *`,
      [phone, name]
    );
    res.json({ success: true, user: result.rows[0] });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/drivers/register', async (req, res) => {
  const { phone, name, car_model, car_number } = req.body;
  try {
    const result = await db.query(
      `INSERT INTO drivers (phone,name,car_model,car_number) VALUES ($1,$2,$3,$4) ON CONFLICT (phone) DO UPDATE SET name=EXCLUDED.name RETURNING *`,
      [phone, name, car_model, car_number]
    );
    res.json({ success: true, driver: result.rows[0] });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.patch('/api/drivers/:id/status', async (req, res) => {
  await db.query('UPDATE drivers SET is_active=$1 WHERE id=$2', [req.body.is_active, req.params.id]);
  res.json({ success: true });
});

app.get('/api/users/:id/favourites', async (req, res) => {
  const result = await db.query('SELECT * FROM favourite_addresses WHERE user_id=$1 ORDER BY created_at DESC', [req.params.id]);
  res.json(result.rows);
});

app.post('/api/users/:id/favourites', async (req, res) => {
  const { label, address, lat, lng } = req.body;
  const result = await db.query(
    `INSERT INTO favourite_addresses (user_id,label,address,lat,lng) VALUES ($1,$2,$3,$4,$5) RETURNING *`,
    [req.params.id, label, address, lat, lng]
  );
  res.json(result.rows[0]);
});

app.delete('/api/users/:userId/favourites/:favId', async (req, res) => {
  await db.query('DELETE FROM favourite_addresses WHERE id=$1 AND user_id=$2', [req.params.favId, req.params.userId]);
  res.json({ success: true });
});

app.get('/api/users/:id/frequent', async (req, res) => {
  const result = await db.query('SELECT * FROM frequent_addresses WHERE user_id=$1 ORDER BY count DESC LIMIT 5', [req.params.id]);
  res.json(result.rows);
});

app.get('/api/admin/drivers/active', async (req, res) => {
  const result = await db.query('SELECT id,name,car_model,car_number,lat,lng,last_seen FROM drivers WHERE is_active=TRUE');
  res.json(result.rows);
});

app.get('/api/admin/orders', async (req, res) => {
  const { status } = req.query;
  const q = status
    ? 'SELECT o.*,u.name as user_name,d.name as driver_name FROM orders o LEFT JOIN users u ON o.user_id=u.id LEFT JOIN drivers d ON o.driver_id=d.id WHERE o.status=$1 ORDER BY o.created_at DESC LIMIT 50'
    : 'SELECT o.*,u.name as user_name,d.name as driver_name FROM orders o LEFT JOIN users u ON o.user_id=u.id LEFT JOIN drivers d ON o.driver_id=d.id ORDER BY o.created_at DESC LIMIT 50';
  const result = await db.query(q, status ? [status] : []);
  res.json(result.rows);
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => console.log(`Master Taxi Gurlan server running on port ${PORT}`));
