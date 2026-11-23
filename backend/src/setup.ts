import { INestApplication, ValidationPipe } from '@nestjs/common';
import helmet from 'helmet';

/** Shared by main.ts and the e2e tests so both run the same pipeline. */
export function configureApp(app: INestApplication) {
  app.use(helmet());
  app.enableCors();
  app.setGlobalPrefix('api/v1', { exclude: ['health'] });
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
}
