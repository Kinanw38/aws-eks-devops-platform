const express = require('express');
const os = require('os');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 8080;
const START_TIME = new Date();

app.use(express.json());
app.use(express.static(path.join(__dirname)));

// REST API Main Endpoint
app.get('/api', (req, res) => {
    res.json({
        service: "SentinelOps Enterprise Microservice Portal",
        status: "Operational",
        environment: process.env.NODE_ENV || "production",
        podName: os.hostname(),
        platform: os.platform(),
        architecture: os.arch(),
        timestamp: new Date().toISOString()
    });
});

// 1. Real Chaos Engineering - Pod Crash Trigger
app.all('/api/crash', (req, res) => {
    res.status(500).json({ status: "CRASHING", message: "Fatal error injected. Exiting process!" });
    setTimeout(() => {
        console.error("CRITICAL: Fatal exit requested. Terminating Node.js process!");
        process.exit(1);
    }, 300);
});

// 2. Real Non-blocking CPU & Memory Stress Endpoint for HPA Test
app.all('/api/stress', async (req, res) => {
    const durationMs = parseInt(req.query.duration) || 8000;
    const startTime = Date.now();
    const tempBuffer = [];

    // אופטימיזציה: הרצת עומס חישובי במקטעי זמן (Chunks) של 40 מילי-שניות.
    // בין מקטע למקטע משחררים את ה-Thread בעזרת setImmediate.
    // זה מעלה את ה-CPU ל-95%-100% עבור HPA & Prometheus,
    // ובמקביל מאפשר לשרת לענות מיידית לקריאות /health ולרענוני UI!
    while (Date.now() - startTime < durationMs) {
        const chunkStart = Date.now();
        while (Date.now() - chunkStart < 40) {
            Math.sqrt(Math.random() * Math.random()) * Math.sin(Math.random());
            if (tempBuffer.length < 200000) {
                tempBuffer.push(new Array(30).fill("HPA_STRESS_BLOCK"));
            }
        }
        await new Promise(resolve => setImmediate(resolve));
    }

    res.json({
        status: "STRESS_COMPLETE",
        durationMs,
        pod: os.hostname(),
        memoryUsageMB: Math.round(process.memoryUsage().heapUsed / 1024 / 1024)
    });
});

// 3. Real Health Probe Endpoint (Used by K8s Probes & UI)
app.get('/health', (req, res) => {
    res.status(200).json({
        status: "UP",
        uptimeSeconds: Math.floor((new Date() - START_TIME) / 1000),
        pod: os.hostname(),
        totalMemoryMB: Math.round(os.totalmem() / 1024 / 1024),
        freeMemoryMB: Math.round(os.freemem() / 1024 / 1024),
        memoryUsageMB: Math.round(process.memoryUsage().heapUsed / 1024 / 1024)
    });
});

// 4. Prometheus Metrics Endpoint
app.get('/metrics', (req, res) => {
    const uptime = Math.floor((new Date() - START_TIME) / 1000);
    const mem = process.memoryUsage().heapUsed;
    res.type('text/plain').send(
        `# HELP http_requests_total Total number of HTTP requests\n` +
        `# TYPE http_requests_total counter\n` +
        `app_uptime_seconds ${uptime}\n` +
        `app_memory_bytes ${mem}\n` +
        `app_health_status 1\n` +
        `k8s_node_healthy 1\n`
    );
});

// 5. Dynamic ConfigMap Injected File Endpoint
app.get('/injected-file', (req, res) => {
    const injectedDir = '/app/injected';
    const defaultFilePath = process.env.INJECTED_FILE_PATH || path.join(injectedDir, 'config.json');

    const tryParseOrRaw = (filePath) => {
        try {
            const raw = fs.readFileSync(filePath, 'utf8');
            try {
                return JSON.parse(raw);
            } catch (e) {
                return raw; // תמיכה בקובץ מוזרק שאינו JSON (טקסט חופשי מג'נקינס)
            }
        } catch (err) {
            return null;
        }
    };

    if (fs.existsSync(defaultFilePath)) {
        const content = tryParseOrRaw(defaultFilePath);
        if (content !== null) {
            return res.json({ status: "success", source: defaultFilePath, content });
        }
    }

    if (fs.existsSync(injectedDir)) {
        try {
            const files = fs.readdirSync(injectedDir).filter(f => !f.startsWith('.'));
            if (files.length > 0) {
                const targetFile = path.join(injectedDir, files[0]);
                const content = tryParseOrRaw(targetFile);
                if (content !== null) {
                    return res.json({ status: "success", source: targetFile, content });
                }
            }
        } catch (e) {}
    }

    // Default response if no file has been injected yet
    res.json({
        status: "success",
        source: "ConfigMap Dynamic Injector (Fallback)",
        content: {
            pipeline: "Jenkins K8s Agent Pipeline #3",
            status: "Success",
            injectedAt: new Date().toISOString(),
            config: { database: "aws-rds-cluster.internal", timeout: "3000ms", featureFlags: { enableV2Api: true } }
        }
    });
});

app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
});

app.listen(PORT, () => {
    console.log(`SentinelOps Portal active on port ${PORT} | Pod: ${os.hostname()}`);
});