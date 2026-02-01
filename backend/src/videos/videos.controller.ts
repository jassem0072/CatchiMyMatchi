import * as fs from 'node:fs';
import * as path from 'node:path';
import { randomUUID } from 'node:crypto';

import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Req,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { diskStorage } from 'multer';
import type { Request, Response } from 'express';

import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';

import { AnalyzeOptions, VideosService } from './videos.service';

function uploadsRoot(): string {
  const uploadDir = process.env.UPLOAD_DIR || 'uploads';
  return path.isAbsolute(uploadDir) ? uploadDir : path.join(process.cwd(), uploadDir);
}

@ApiTags('videos')
@Controller('videos')
export class VideosController {
  constructor(private readonly videosService: VideosService) {}

  @Post()
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: (_req: Request, _file: Express.Multer.File, cb: (error: Error | null, destination: string) => void) => {
          const root = uploadsRoot();
          fs.mkdirSync(root, { recursive: true });
          cb(null, root);
        },
        filename: (_req: Request, file: Express.Multer.File, cb: (error: Error | null, filename: string) => void) => {
          const ext = path.extname(file.originalname || '') || '.mp4';
          cb(null, `${randomUUID()}${ext}`);
        },
      }),
      limits: {
        fileSize: 1024 * 1024 * 1024, // 1GB
      },
    }),
  )
  async upload(@UploadedFile() file: Express.Multer.File) {
    return this.videosService.createFromUpload(file, null);
  }

  @Get()
  async list() {
    return this.videosService.list();
  }

  @Get(':id')
  async get(@Param('id') id: string) {
    return this.videosService.getById(id);
  }

  @Post(':id/analyze')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('scouter')
  async analyze(@Param('id') id: string, @Body() body: AnalyzeOptions) {
    return this.videosService.analyzeVideo(id, body);
  }

  @Get(':id/stream')
  async stream(@Param('id') id: string, @Req() req: Request, @Res() res: Response) {
    const video = await this.videosService.getById(id);
    const filePath = await this.videosService.getAbsolutePath(video);

    const stat = fs.statSync(filePath);
    const fileSize = stat.size;
    const range = req.headers.range;

    res.setHeader('Content-Type', video.mimeType || 'video/mp4');
    res.setHeader('Accept-Ranges', 'bytes');

    if (!range) {
      res.setHeader('Content-Length', fileSize);
      fs.createReadStream(filePath).pipe(res);
      return;
    }

    const match = /^bytes=(\d+)-(\d*)$/.exec(range);
    if (!match) {
      res.status(416).end();
      return;
    }

    const start = Number(match[1]);
    const end = match[2] ? Number(match[2]) : fileSize - 1;

    if (Number.isNaN(start) || Number.isNaN(end) || start >= fileSize || end >= fileSize) {
      res.status(416).end();
      return;
    }

    const chunkSize = end - start + 1;
    res.status(206);
    res.setHeader('Content-Range', `bytes ${start}-${end}/${fileSize}`);
    res.setHeader('Content-Length', chunkSize);

    fs.createReadStream(filePath, { start, end }).pipe(res);
  }
}
