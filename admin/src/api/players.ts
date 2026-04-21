import client from './client';
import type { AdminPlayer, PlayerDetail, PaginatedResponse } from '../types';

export interface PlayersQuery {
    page?: number;
    limit?: number;
    search?: string;
    subscriptionTier?: string;
}

export async function getPlayers(query: PlayersQuery = {}): Promise<PaginatedResponse<AdminPlayer>> {
    const params: Record<string, string | number> = {};
    if (query.page) params.page = query.page;
    if (query.limit) params.limit = query.limit;
    if (query.search) params.search = query.search;
    if (query.subscriptionTier) params.subscriptionTier = query.subscriptionTier;
    const res = await client.get<PaginatedResponse<AdminPlayer>>('/admin/players', { params });
    return res.data;
}

export async function getPlayerDetail(id: string): Promise<PlayerDetail> {
    const res = await client.get<PlayerDetail>(`/admin/players/${id}`);
    return res.data;
}
