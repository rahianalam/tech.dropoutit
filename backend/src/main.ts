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
}
bootstrap();
