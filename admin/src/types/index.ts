export type UserRole = 'player' | 'scouter' | 'admin';
export type SubscriptionTier = 'basic' | 'premium' | 'elite';

export interface AdminUser {
  _id: string;
  email: string;
  displayName: string;
  role: UserRole;
  position?: string;
  nation?: string;
  dateOfBirth?: string | null;
  height?: number | null;
  emailVerified: boolean;
  isBanned: boolean;
  subscriptionTier?: SubscriptionTier | null;
  subscriptionExpiresAt?: string | null;
  badgeVerified: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface AdminPlayer extends AdminUser {
  videoCount: number;
  reportCount: number;
}

export interface AdminScouter extends AdminUser {
  reportCount: number;
  isExpired: boolean;
  expiresInDays: number | null;
}

export interface PlayerAnalytics {
  totalVideos: number;
  analyzedVideos: number;
  totalDistanceMeters: number;
  avgSpeedKmh: number;
  maxSpeedKmh: number;
  totalSprints: number;
  reportsAboutPlayer: number;
}

export interface PlayerDetail {
  player: AdminPlayer;
  videos: AdminVideo[];
  reports: AdminReport[];
  analytics: PlayerAnalytics;
}

export interface ScouterDetail {
  scouter: AdminScouter;
  reports: (AdminReport & { playerDisplayName: string })[];
  isExpired: boolean;
}

export interface AdminAnalytics {
  activeSubscriptions: number;
  expiringSoon: number;
  bannedUsers: number;
  totalReports: number;
  revenueByTier: { basic: number; premium: number; elite: number };
  revenueTotal: number;
  topScouters: { _id: string; displayName: string; reportCount: number }[];
  topPlayers: { _id: string; displayName: string; position: string; reportCount: number }[];
}

export interface AdminVideo {
  _id: string;
  ownerId?: string | null;
  ownerDisplayName: string;
  filename: string;
  originalName: string;
  mimeType: string;
  size: number;
  visibility: 'public' | 'private';
  taggedPlayers: string[];
  lastAnalysis?: Record<string, unknown> | null;
  lastAnalysisAt?: string;
  createdAt: string;
  updatedAt: string;
}

export interface AdminReport {
  _id: string;
  scouterId: string;
  playerId: string;
  videoId?: string | null;
  title: string;
  notes: string;
  createdAt: string;
  updatedAt: string;
}

export interface Stats {
  totalPlayers: number;
  totalScouterss: number;
  totalVideos: number;
  analyzedVideos: number;
  registrations: Array<{ label: string; count: number }>;
  subscriptions: { basic: number; premium: number; elite: number };
}

export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page: number;
  limit: number;
}

export interface AuthResponse {
  accessToken: string;
}
