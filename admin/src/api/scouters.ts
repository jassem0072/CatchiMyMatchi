import client from './client';
import type { AdminScouter, AdminUser, ScouterDetail, PaginatedResponse } from '../types';

export interface ScoutersQuery {
    page?: number;
    limit?: number;
    search?: string;
    subscriptionTier?: string;
}

export async function getScouters(query: ScoutersQuery = {}): Promise<PaginatedResponse<AdminScouter>> {
    const params: Record<string, string | number> = {};
    if (query.page) params.page = query.page;
    if (query.limit) params.limit = query.limit;
    if (query.search) params.search = query.search;
    if (query.subscriptionTier) params.subscriptionTier = query.subscriptionTier;
    const res = await client.get<PaginatedResponse<AdminScouter>>('/admin/scouters', { params });
    return res.data;
}

export async function getScouterDetail(id: string): Promise<ScouterDetail> {
    const res = await client.get<ScouterDetail>(`/admin/scouters/${id}`);
    return res.data;
}

export async function updateSubscription(
    userId: string,
    tier: string | null,
    expiresAt: string | null,
): Promise<AdminUser> {
    const res = await client.patch<AdminUser>(`/admin/users/${userId}/subscription`, { tier, expiresAt });
    return res.data;
}
