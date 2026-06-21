const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { exec } = require('child_process');

const PORT = 18000;
const EXPORT_DIR = __dirname;

// Placeholders replaced by Godot export plugin
const GAME_NAME = "{{GAME_NAME}}";
const GAME_VERSION = "{{GAME_VERSION}}";
const GODOT_VERSION = "{{GODOT_VERSION}}";
const BUILD_TIME = "{{BUILD_TIME}}";

const MIME_TYPES = {
	'.html': 'text/html',
	'.css': 'text/css',
	'.js': 'application/javascript',
	'.json': 'application/json',
	'.png': 'image/png',
	'.jpg': 'image/jpeg',
	'.jpeg': 'image/jpeg',
	'.ico': 'image/x-icon',
	'.wasm': 'application/wasm',
	'.pck': 'application/octet-stream',
	'.ogg': 'audio/ogg',
	'.wav': 'audio/wav'
};

const server = http.createServer((req, res) => {
	// CORS Headers
	res.setHeader('Access-Control-Allow-Origin', '*');
	// Cross-Origin Isolation Headers (crucial for Godot Web Exports to run properly)
	res.setHeader('Access-Control-Opener-Policy', 'same-origin');
	res.setHeader('Access-Control-Embedder-Policy', 'require-corp');

	const reqPath = req.url.split('?')[0];
	let filePath = path.join(EXPORT_DIR, reqPath);
	if (req.url === '/' || req.url === '') {
		filePath = path.join(EXPORT_DIR, 'index.html');
	}

	fs.stat(filePath, (err, stats) => {
		if (err || !stats.isFile()) {
			res.writeHead(404, { 'Content-Type': 'text/plain' });
			res.end('404 Not Found: ' + req.url);
			return;
		}

		const ext = path.extname(filePath).toLowerCase();
		const contentType = MIME_TYPES[ext] || 'application/octet-stream';

		res.writeHead(200, { 'Content-Type': contentType });
		fs.createReadStream(filePath).pipe(res);
	});
});

let currentPort = PORT;

server.on('error', (err) => {
	if (err.code === 'EADDRINUSE') {
		console.log(`Port ${currentPort} is in use, trying port ${currentPort + 1}...`);
		currentPort++;
		server.listen(currentPort);
	} else {
		console.error('Server error:', err);
	}
});

function getLocalIp() {
	const interfaces = os.networkInterfaces();
	for (const name of Object.keys(interfaces)) {
		for (const iface of interfaces[name]) {
			if (iface.family === 'IPv4' && !iface.internal) {
				return iface.address;
			}
		}
	}
	return null;
}

server.on('listening', () => {
	const localIp = getLocalIp();
	const displayTitle = GAME_NAME.startsWith('{{') ? 'GODOT WEB EXPORT' : GAME_NAME.toUpperCase();
	const displayVersion = GAME_VERSION.startsWith('{{') ? '1.0.0' : GAME_VERSION;
	const displayGodot = GODOT_VERSION.startsWith('{{') ? '3.x (Unknown)' : GODOT_VERSION;
	const displayBuild = BUILD_TIME.startsWith('{{') ? 'Development Server' : BUILD_TIME;

	console.log(`\n======================================================`);
	console.log(`  ${displayTitle}`);
	console.log(`======================================================`);
	console.log(`Game Name:    ${GAME_NAME.startsWith('{{') ? 'Godot Web Game' : GAME_NAME}`);
	console.log(`Version:      ${displayVersion}`);
	console.log(`Godot Engine: ${displayGodot}`);
	console.log(`Build Time:   ${displayBuild}`);
	console.log(`Platform:     HTML5 / WebAssembly`);
	console.log(`------------------------------------------------------`);
	console.log(`Local URL:    http://localhost:${currentPort}`);
	if (localIp) {
		console.log(`Network URL:  http://${localIp}:${currentPort} (For mobile testing)`);
	}
	console.log(`Serving from: ${EXPORT_DIR}`);
	console.log(`======================================================`);
	console.log(`To stop the server, press Ctrl+C in this window.\n`);
	
	// Automatically open the game in the default browser (Windows)
	exec(`start http://localhost:${currentPort}`, (err) => {
		if (err) {
			console.error('Failed to open browser:', err);
		}
	});
});

server.listen(PORT);
