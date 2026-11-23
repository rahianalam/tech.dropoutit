process.env.PAYMENT_GATEWAY = 'fake';
process.env.SCHEDULER_DISABLED = 'true';
process.env.JWT_ACCESS_SECRET ??= 'test-secret';
process.env.UPLOAD_DIR = require('path').join(require('os').tmpdir(), 'techdropout-test-uploads');
