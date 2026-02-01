import * as fs from 'node:fs';
import * as path from 'node:path';
import { randomUUID } from 'node:crypto';

import {
  BadRequestException,
  Controller,
  Get,
  NotFoundException,
  Post,
  Req,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { diskStorage, memoryStorage } from 'multer';
import type { Request, Response } from 'express';
import { ApiBearerAuth, ApiBody, ApiConsumes, ApiTags } from '@nestjs/swagger';

import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import type { RequestUser } from '../auth/request-user';
import { UsersService } from '../users/users.service';
import { VideosService } from '../videos/videos.service';

function normalizePortraitContentType(file: Express.Multer.File): string {
  const ct = (file.mimetype || '').toLowerCase();
  if (ct.startsWith('image/')) return ct;

  const ext = path.extname(file.originalname || '').toLowerCase();
  if (ext === '.png') return 'image/png';
  if (ext === '.webp') return 'image/webp';
  if (ext === '.gif') return 'image/gif';
  if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
  return 'image/jpeg';
}

function uploadsRoot(): string {
  const uploadDir = process.env.UPLOAD_DIR || 'uploads';
  return path.isAbsolute(uploadDir) ? uploadDir : path.join(process.cwd(), uploadDir);
}

@ApiTags('me')
@ApiBearerAuth()
@Controller('me')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('player')
export class MeController {
  constructor(
    private readonly videos: VideosService,
    private readonly users: UsersService,
  ) {}

  @Get('videos')
  async myVideos(@Req() req: { user?: RequestUser }) {
    const me = req.user!;
    return this.videos.listByOwner(me.sub);
  }

  @Post('videos')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: (
          _req: Request,
          _file: Express.Multer.File,
          cb: (error: Error | null, destination: string) => void,
        ) => {
          const root = uploadsRoot();
          fs.mkdirSync(root, { recursive: true });
          cb(null, root);
        },
        filename: (
          _req: Request,
          file: Express.Multer.File,
          cb: (error: Error | null, filename: string) => void,
        ) => {
          const ext = path.extname(file.originalname || '') || '.mp4';
          cb(null, `${randomUUID()}${ext}`);
        },
      }),
      limits: {
        fileSize: 1024 * 1024 * 1024,
      },
    }),
  )
  async uploadMyVideo(@Req() req: { user?: RequestUser }, @UploadedFile() file: Express.Multer.File) {
    const me = req.user!;
    return this.videos.createFromUpload(file, me.sub);
  }

  @Post('portrait')
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: {
        file: { type: 'string', format: 'binary' },
      },
      required: ['file'],
    },
  })
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      limits: {
        fileSize: 10 * 1024 * 1024,
      },
    }),
  )
  async uploadPortrait(@Req() req: { user?: RequestUser }, @UploadedFile() file: Express.Multer.File) {
    if (!file) throw new BadRequestException('file is required');
    const me = req.user!;
    console.log('[me/portrait] upload start', {
      userId: me.sub,
      originalname: file.originalname,
      mimetype: file.mimetype,
      size: (file as any).size ?? file.buffer?.length ?? 0,
    });
    if (!file.buffer || file.buffer.length === 0) throw new BadRequestException('file is required');
    const contentType = normalizePortraitContentType(file);
    const updated = await this.users.setPortraitData(me.sub, file.buffer, contentType);
    const { passwordHash, ...safe } = updated as any;
    console.log('[me/portrait] upload saved', { userId: me.sub, contentType, bytes: file.buffer.length });
    return safe;
  }

  @Get('portrait')
  async getPortrait(@Req() req: { user?: RequestUser }, @Res() res: Response) {
    const me = req.user!;
    const portrait = await this.users.getPortraitForUserOrMigrateFromFile(me.sub);
    if (!portrait) throw new NotFoundException('Portrait not found');
    const data: any = portrait.data as any;
    const bytes = Buffer.isBuffer(data)
      ? data.length
      : data instanceof Uint8Array
        ? data.byteLength
        : typeof data?.length === 'number'
          ? data.length
          : typeof data?.length === 'function'
            ? data.length()
            : 0;
    console.log('[me/portrait] get', { userId: me.sub, contentType: portrait.contentType, bytes });
    res.setHeader('Content-Type', portrait.contentType || 'image/jpeg');
    res.setHeader('Cache-Control', 'no-store');
    return res.send(Buffer.isBuffer(data) ? data : Buffer.from(data));
  }
}
