// Firebase CLI login: Node keep-alive "Premature close" muammosi uchun.
require('http').globalAgent.keepAlive = false;
require('https').globalAgent.keepAlive = false;
