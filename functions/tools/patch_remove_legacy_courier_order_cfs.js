const fs = require('fs');
const p = require('path').join(__dirname, '..', 'index.js');
let s = fs.readFileSync(p, 'utf8');

const start1 = s.indexOf('/** Курьер: `courier_orders`');
const start2 = s.indexOf('exports.requestPayout');
if (start1 < 0 || start2 < 0 || start1 >= start2) {
  console.error('markers not found', start1, start2);
  process.exit(1);
}
s = s.slice(0, start1) + s.slice(start2);
if (s.includes('courierMarkCourierOrderArrived') || s.includes('courierSubmitCourierOrderPayment')) {
  console.error('still present');
  process.exit(1);
}
fs.writeFileSync(p, s);
console.log('removed legacy courier_order CF block');
