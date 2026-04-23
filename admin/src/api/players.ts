import client from './client';
import type { AdminPlayer, PlayerDetail, PaginatedResponse, PlayerWorkflow } from '../types';

export interface PlayerDocumentFile {
    blob: Blob;
    contentType: string;
    fileName: string;
}

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

export async function sendPlayerVideoRequest(id: string): Promise<PlayerWorkflow> {
    const res = await client.post<{ workflow: PlayerWorkflow }>(`/admin/players/${id}/video-request`);
    return res.data.workflow;
}

export async function requestPlayerInfoVerification(id: string): Promise<PlayerWorkflow> {
    const res = await client.post<{ workflow: PlayerWorkflow }>(`/admin/players/${id}/request-info-verification`);
    return res.data.workflow;
}

export async function submitExpertReview(
    id: string,
    payload: {
        decision: 'approved' | 'cancelled';
        report?: string;
    },
): Promise<PlayerWorkflow> {
    const res = await client.patch<{ workflow: PlayerWorkflow }>(`/admin/players/${id}/expert-review`, payload);
    return res.data.workflow;
}

export async function submitScouterDecision(
    id: string,
    payload: { decision: 'approved' | 'cancelled' },
): Promise<PlayerWorkflow> {
    const res = await client.patch<{ workflow: PlayerWorkflow }>(`/admin/players/${id}/scouter-decision`, payload);
    return res.data.workflow;
}

export async function updatePreContract(
    id: string,
    payload: {
        fixedPrice?: number;
        status?: 'none' | 'draft' | 'approved' | 'cancelled';
        clubName?: string;
        clubOfficialName?: string;
        startDate?: string;
        endDate?: string;
        currency?: string;
        salaryPeriod?: 'monthly' | 'weekly';
        fixedBaseSalary?: number;
        signingOnFee?: number;
        marketValue?: number;
        bonusPerAppearance?: number;
        bonusGoalOrCleanSheet?: number;
        bonusTeamTrophy?: number;
        releaseClauseAmount?: number;
        terminationForCauseText?: string;
        scouterIntermediaryId?: string;
        scouterSignNow?: boolean;
    },
): Promise<{ workflow: PlayerWorkflow; signatureClauseAmount: number }> {
    const res = await client.patch<{ workflow: PlayerWorkflow; signatureClauseAmount: number }>(`/admin/players/${id}/pre-contract`, payload);
    return res.data;
}

export async function getPlayerPortraitDocument(id: string): Promise<PlayerDocumentFile | null> {
    const res = await client.get<Blob>(`/admin/players/${id}/documents/portrait`, {
        responseType: 'blob',
        validateStatus: (status) => (status >= 200 && status < 300) || status === 204,
    });
    if (res.status === 204 || !res.data || (res.data as any).size === 0) return null;
    const contentType = String(res.headers['content-type'] || 'application/octet-stream');
    const contentDisposition = String(res.headers['content-disposition'] || '');
    const fileNameMatch = /filename="?([^";]+)"?/i.exec(contentDisposition);
    return {
        blob: res.data,
        contentType,
        fileName: fileNameMatch?.[1] || 'bulletin-n3',
    };
}

export async function getPlayerBadgeDocument(id: string): Promise<PlayerDocumentFile | null> {
    const res = await client.get<Blob>(`/admin/players/${id}/documents/badge`, {
        responseType: 'blob',
        validateStatus: (status) => (status >= 200 && status < 300) || status === 204,
    });
    if (res.status === 204 || !res.data || (res.data as any).size === 0) return null;
    const contentType = String(res.headers['content-type'] || 'application/octet-stream');
    const contentDisposition = String(res.headers['content-disposition'] || '');
    const fileNameMatch = /filename="?([^";]+)"?/i.exec(contentDisposition);
    return {
        blob: res.data,
        contentType,
        fileName: fileNameMatch?.[1] || 'medical-diploma',
    };
}

export async function getPlayerIdDocument(id: string): Promise<PlayerDocumentFile | null> {
    const res = await client.get<Blob>(`/admin/players/${id}/documents/player-id`, {
        responseType: 'blob',
        validateStatus: (status) => (status >= 200 && status < 300) || status === 204,
    });
    if (res.status === 204 || !res.data || (res.data as any).size === 0) return null;
    const contentType = String(res.headers['content-type'] || 'application/octet-stream');
    const contentDisposition = String(res.headers['content-disposition'] || '');
    const fileNameMatch = /filename="?([^";]+)"?/i.exec(contentDisposition);
    return {
        blob: res.data,
        contentType,
        fileName: fileNameMatch?.[1] || 'player-id',
    };
}
