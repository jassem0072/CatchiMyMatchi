import 'reflect-metadata';
import 'dotenv/config';

import * as fs from 'node:fs';
import * as path from 'node:path';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  const uploadDir = process.env.UPLOAD_DIR || 'uploads';
  const uploadAbs = path.isAbsolute(uploadDir) ? uploadDir : path.join(process.cwd(), uploadDir);
  fs.mkdirSync(uploadAbs, { recursive: true });

  const corsOrigins = (process.env.CORS_ORIGINS || '*').split(',').map((s) => s.trim());
  app.enableCors({
    origin: corsOrigins.includes('*') ? true : corsOrigins,
    credentials: false,
  });

  const swaggerEnabled = (process.env.SWAGGER_ENABLED || '1') === '1';
  if (swaggerEnabled) {
    const config = new DocumentBuilder()
      .setTitle('ScoutAI API')
      .setDescription('Scouting platform backend')
      .setVersion('0.1.0')
      .addBearerAuth()
      .build();
    const document = SwaggerModule.createDocument(app, config);
    SwaggerModule.setup('docs', app, document);
  }

  const port = Number(process.env.PORT || 3000);
  await app.listen(port);
}

bootstrap();
