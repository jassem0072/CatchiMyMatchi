import bcrypt from 'bcryptjs';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { randomUUID } from 'node:crypto';
import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';

import { User, UserDocument, UserRole } from './users.schema';

export type CreateUserInput = {
  email: string;
  password: string;
  role: UserRole;
  displayName?: string;
  position?: string;
  nation?: string;
};

@Injectable()
export class UsersService {
  constructor(@InjectModel(User.name) private readonly userModel: Model<UserDocument>) {}

  private coerceToBuffer(value: any): Buffer | null {
    if (!value) return null;
    if (Buffer.isBuffer(value)) return value;
    if (value instanceof Uint8Array) return Buffer.from(value);

    if (typeof value === 'object') {
      if (value.type === 'Buffer' && Array.isArray(value.data)) {
        return Buffer.from(value.data);
      }

      const bsontype = (value as any)._bsontype;
      if (bsontype === 'Binary' && typeof (value as any).value === 'function') {
        const v = (value as any).value(true);
        if (Buffer.isBuffer(v)) return v;
        if (v instanceof Uint8Array) return Buffer.from(v);
        if (Array.isArray(v)) return Buffer.from(v);
      }

      const buf = (value as any).buffer;
      if (Buffer.isBuffer(buf)) return buf;
      if (buf instanceof Uint8Array) return Buffer.from(buf);
    }

    try {
      return Buffer.from(value);
    } catch {
      return null;
    }
  }

  async findByGoogleSub(googleSub: string): Promise<UserDocument | null> {
    const sub = (googleSub || '').trim();
    if (!sub) return null;
    return this.userModel.findOne({ googleSub: sub });
  }

  async createOrUpdateGoogleUser(input: {
    email: string;
    googleSub: string;
    displayName?: string;
    role?: UserRole;
  }): Promise<UserDocument> {
    const email = (input.email || '').trim().toLowerCase();
    const googleSub = (input.googleSub || '').trim();
    if (!email) throw new BadRequestException('email is required');
    if (!googleSub) throw new BadRequestException('googleSub is required');

    const existing = await this.userModel.findOne({ $or: [{ email }, { googleSub }] });
    if (existing) {
      const updated = await this.userModel.findByIdAndUpdate(
        existing._id,
        {
          email,
          googleSub,
          ...(input.displayName && input.displayName.trim()
            ? { displayName: input.displayName.trim() }
            : {}),
        },
        { new: true },
      );
      if (!updated) throw new NotFoundException('User not found');
      return updated;
    }

    if (!input.role) throw new BadRequestException('role is required');

    const passwordHash = await bcrypt.hash(randomUUID(), 10);
    const created = await this.userModel.create({
      email,
      passwordHash,
      role: input.role,
      displayName: input.displayName || '',
      position: '',
      nation: '',
      googleSub,
    });
    return created;
  }

  async createUser(input: CreateUserInput): Promise<UserDocument> {
    const email = (input.email || '').trim().toLowerCase();
    if (!email) throw new BadRequestException('email is required');
    if (!input.password || input.password.length < 6) throw new BadRequestException('password must be at least 6 chars');

    const existing = await this.userModel.findOne({ email }).lean();
    if (existing) throw new BadRequestException('email already in use');

    const passwordHash = await bcrypt.hash(input.password, 10);
    const created = await this.userModel.create({
      email,
      passwordHash,
      role: input.role,
      displayName: input.displayName || '',
      position: input.position || '',
      nation: input.nation || '',
    });

    return created;
  }

  async findByEmail(email: string): Promise<UserDocument | null> {
    const e = (email || '').trim().toLowerCase();
    if (!e) return null;
    return this.userModel.findOne({ email: e });
  }

  async setResetPasswordTokenByEmail(
    email: string,
    tokenHash: string,
    expiresAt: Date,
  ): Promise<boolean> {
    const u = await this.findByEmail(email);
    if (!u) return false;
    u.resetPasswordTokenHash = tokenHash;
    u.resetPasswordExpiresAt = expiresAt;
    await u.save();
    return true;
  }

  async resetPasswordByToken(email: string, tokenHash: string, newPassword: string): Promise<void> {
    const password = newPassword || '';
    if (password.length < 6) throw new BadRequestException('password must be at least 6 chars');

    const u = await this.findByEmail(email);
    if (!u) throw new BadRequestException('Invalid reset token');

    const expected = (u.resetPasswordTokenHash || '').trim();
    const expiresAt = u.resetPasswordExpiresAt ? new Date(u.resetPasswordExpiresAt) : null;
    if (!expected || expected !== tokenHash) throw new BadRequestException('Invalid reset token');
    if (!expiresAt || expiresAt.getTime() < Date.now()) throw new BadRequestException('Reset token expired');

    u.passwordHash = await bcrypt.hash(password, 10);
    u.resetPasswordTokenHash = '';
    u.resetPasswordExpiresAt = null;
    await u.save();
  }

  async getById(id: string): Promise<any> {
    const u = await this.userModel
      .findById(id)
      .select('-portraitData -resetPasswordTokenHash -resetPasswordExpiresAt')
      .lean();
    if (!u) throw new NotFoundException('User not found');
    return u;
  }

  async getPortraitForUser(id: string): Promise<{ data: Buffer; contentType: string } | null> {
    const u: any = await this.userModel
      .findById(id)
      .select('portraitData portraitContentType')
      .lean();
    if (!u) throw new NotFoundException('User not found');
    const data = this.coerceToBuffer(u.portraitData);
    if (!data || data.length === 0) return null;
    return {
      data,
      contentType: (u.portraitContentType as string) || 'image/jpeg',
    };
  }

  async getPortraitForUserOrMigrateFromFile(
    id: string,
  ): Promise<{ data: Buffer; contentType: string } | null> {
    const fromDb = await this.getPortraitForUser(id);
    if (fromDb) return fromDb;

    const u: any = await this.userModel.findById(id).select('portraitFile').lean();
    if (!u) throw new NotFoundException('User not found');
    const portraitFile = (u.portraitFile as string) || '';
    if (!portraitFile) return null;

    const uploadDir = process.env.UPLOAD_DIR || 'uploads';
    const uploadsRoot = path.isAbsolute(uploadDir) ? uploadDir : path.join(process.cwd(), uploadDir);
    const portraitsRoot = path.join(uploadsRoot, 'portraits');
    const filePath = path.join(portraitsRoot, portraitFile);
    if (!fs.existsSync(filePath)) return null;

    const data = fs.readFileSync(filePath);
    const ext = path.extname(portraitFile).toLowerCase();
    const contentType =
      ext === '.png'
        ? 'image/png'
        : ext === '.webp'
          ? 'image/webp'
          : ext === '.gif'
            ? 'image/gif'
            : 'image/jpeg';

    await this.setPortraitData(id, data, contentType);
    return { data, contentType };
  }

  async setPortraitFile(id: string, portraitFile: string): Promise<any> {
    const u = await this.userModel.findByIdAndUpdate(id, { portraitFile }, { new: true }).lean();
    if (!u) throw new NotFoundException('User not found');
    return u;
  }

  async setPortraitData(id: string, portraitData: Buffer, portraitContentType: string): Promise<any> {
    const u = await this.userModel
      .findByIdAndUpdate(
        id,
        {
          portraitData,
          portraitContentType,
          portraitFile: '',
        },
        { new: true },
      )
      .select('-portraitData')
      .lean();
    if (!u) throw new NotFoundException('User not found');
    return u;
  }

  async listPlayers(): Promise<any[]> {
    return this.userModel
      .find({ role: 'player' })
      .select('-passwordHash -portraitData -resetPasswordTokenHash -resetPasswordExpiresAt')
      .sort({ createdAt: -1 })
      .lean();
  }
}
