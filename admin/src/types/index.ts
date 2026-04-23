export type UserRole = 'player' | 'scouter' | 'admin' | 'expert';
export type SubscriptionTier = 'basic' | 'premium' | 'elite';

export interface AdminUser {
  _id: string;
  email: string;
  displayName: string;
  role: UserRole;
  adminAccessRequestStatus?: 'none' | 'pending' | 'approved' | 'rejected';
  adminAccessRequestedAt?: string | null;
  adminAccessApprovedAt?: string | null;
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
  adminWorkflow?: {
    verificationStatus?: 'not_requested' | 'pending_expert' | 'verified' | 'rejected';
    updatedAt?: string;
  };
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
  workflow?: PlayerWorkflow;
}

export interface PlayerWorkflow {
  sentVideoRequests: number;
  verificationStatus: 'not_requested' | 'pending_expert' | 'verified' | 'rejected';
  scouterDecision: 'pending' | 'approved' | 'cancelled';
  expertDecision: 'pending' | 'approved' | 'cancelled';
  expertReport: string;
  fixedPrice: number;
  preContractStatus: 'none' | 'draft' | 'approved' | 'cancelled';
  contractDraft?: {
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
  };
  scouterSignedContract?: boolean;
  scouterSignedAt?: string | null;
  scouterSignatureName?: string;
  contractSignedByPlayer?: boolean;
  contractSignedAt?: string | null;
  onlineSessionCompleted?: boolean;
  onlineSessionCompletedAt?: string | null;
  contractCompleted?: boolean;
  updatedAt: string;
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
  scouterDisplayName?: string;
  playerDisplayName?: string;
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
