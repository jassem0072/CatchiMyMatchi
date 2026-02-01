import { BadRequestException, Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';

import { Favorite, FavoriteDocument } from './favorites.schema';

@Injectable()
export class FavoritesService {
  constructor(@InjectModel(Favorite.name) private readonly favModel: Model<FavoriteDocument>) {}

  async add(scouterId: string, playerId: string): Promise<Favorite> {
    if (!playerId) throw new BadRequestException('playerId is required');
    try {
      const created = await this.favModel.create({ scouterId, playerId });
      return created.toObject();
    } catch {
      // ignore duplicate
      const existing = await this.favModel.findOne({ scouterId, playerId }).lean();
      if (!existing) throw new BadRequestException('Failed to add favorite');
      return existing;
    }
  }

  async remove(scouterId: string, playerId: string): Promise<{ ok: true }> {
    await this.favModel.deleteOne({ scouterId, playerId });
    return { ok: true };
  }

  async list(scouterId: string): Promise<Favorite[]> {
    return this.favModel.find({ scouterId }).sort({ createdAt: -1 }).lean();
  }

  async isFavorite(scouterId: string, playerId: string): Promise<boolean> {
    const f = await this.favModel.findOne({ scouterId, playerId }).lean();
    return Boolean(f);
  }
}
