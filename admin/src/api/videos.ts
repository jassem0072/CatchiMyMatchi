import client from './client';
import type { AdminVideo, PaginatedResponse } from '../types';

export async function getVideos(page = 1, limit = 20): Promise<PaginatedResponse<AdminVideo>> {
  const res = await client.get<PaginatedResponse<AdminVideo>>('/admin/videos', { params: { page, limit } });
  return res.data;
}

export async function deleteVideo(id: string): Promise<void> {
  await client.delete(`/admin/videos/${id}`);
}

export async function setVideoVisibility(id: string, visibility: 'public' | 'private'): Promise<AdminVideo> {
  const res = await client.patch<AdminVideo>(`/admin/videos/${id}/visibility`, { visibility });
  return res.data;
}
