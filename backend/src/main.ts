import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { configureApp } from './setup';

async function bootstrap() {
  for (const key of ['DATABASE_URL', 'JWT_ACCESS_SECRET']) {
    if (!process.env[key]) throw new Error(`${key} is not set`);
  }
  const app = await NestFactory.create(AppModule);
  configureApp(app);
  app.enableShutdownHooks();
  await app.listen(Number(process.env.PORT ?? 3000));
  // Node closes requests after 5 minutes by default; a 2 GB lesson video on a slow
  // connection takes longer, so allow up to 2 hours per request.
  const server = app.getHttpServer();
  server.requestTimeout = 2 * 60 * 60 * 1000;
  server.headersTimeout = 60 * 1000;
}
bootstrap();
