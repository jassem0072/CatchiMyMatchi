import {
  BadRequestException,
  Injectable,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';

import { Team, TeamDocument } from './teams.schema';
import { NotificationsService } from '../notifications/notifications.service';
import { UsersService } from '../users/users.service';

@Injectable()
export class TeamsService {
  constructor(
    @InjectModel(Team.name) private readonly teamModel: Model<TeamDocument>,
    private readonly notifSvc: NotificationsService,
    private readonly usersSvc: UsersService,
  ) {}

  /** Create a new team — owner is auto-added as member */
  async create(ownerId: string, name: string): Promise<Team> {
    const trimmed = (name || '').trim();
    if (!trimmed) throw new BadRequestException('Team name is required');

    const doc = await this.teamModel.create({
      ownerId,
      name: trimmed,
      members: [ownerId],
      pendingInvites: [],
    });
    return doc.toObject();
  }

  /** Get all teams a user belongs to (as member) */
  async listByMember(userId: string): Promise<Team[]> {
    return this.teamModel.find({ members: userId }).sort({ createdAt: -1 }).lean();
  }

  /** Get a team by id */
  async getById(id: string): Promise<any> {
    const t = await this.teamModel.findById(id).lean();
    if (!t) throw new NotFoundException('Team not found');
    return t;
  }

  /** Invite a player to a team — only team owner can invite */
  async invite(teamId: string, requesterId: string, targetUserId: string): Promise<void> {
    const team = await this.teamModel.findById(teamId);
    if (!team) throw new NotFoundException('Team not found');
    if (team.ownerId !== requesterId) throw new ForbiddenException('Only the team owner can invite');
    if (team.members.includes(targetUserId)) throw new BadRequestException('Already a member');
    if (team.pendingInvites.includes(targetUserId)) throw new BadRequestException('Invitation already sent');

    // Verify target user exists and is a player
    const targetUser = await this.usersSvc.getById(targetUserId);
    if (!targetUser) throw new NotFoundException('Player not found');

    team.pendingInvites.push(targetUserId);
    await team.save();

    // Get inviter name
    const inviter = await this.usersSvc.getById(requesterId);
    const inviterName = inviter?.displayName || 'A player';

    // Send notification to the invited player
    await this.notifSvc.create({
      userId: targetUserId,
      type: 'team_invite',
      titleEN: 'Team Invitation',
      titleFR: 'Invitation d\'équipe',
      bodyEN: `${inviterName} invited you to join "${team.name}".`,
      bodyFR: `${inviterName} vous a invité à rejoindre "${team.name}".`,
      data: { teamId: (team._id as any).toString(), teamName: team.name, inviterId: requesterId },
    });
  }

  /** Accept a team invitation */
  async acceptInvite(teamId: string, userId: string): Promise<void> {
    const team = await this.teamModel.findById(teamId);
    if (!team) throw new NotFoundException('Team not found');

    const idx = team.pendingInvites.indexOf(userId);
    if (idx === -1) throw new BadRequestException('No pending invitation');

    team.pendingInvites.splice(idx, 1);
    if (!team.members.includes(userId)) {
      team.members.push(userId);
    }
    await team.save();

    // Notify team owner
    const joiner = await this.usersSvc.getById(userId);
    const joinerName = joiner?.displayName || 'A player';
    await this.notifSvc.create({
      userId: team.ownerId,
      type: 'team_member_joined',
      titleEN: 'New Team Member!',
      titleFR: 'Nouveau membre !',
      bodyEN: `${joinerName} joined your team "${team.name}".`,
      bodyFR: `${joinerName} a rejoint votre équipe "${team.name}".`,
      data: { teamId: (team._id as any).toString(), teamName: team.name },
    });
  }

  /** Decline a team invitation */
  async declineInvite(teamId: string, userId: string): Promise<void> {
    const team = await this.teamModel.findById(teamId);
    if (!team) throw new NotFoundException('Team not found');

    const idx = team.pendingInvites.indexOf(userId);
    if (idx === -1) throw new BadRequestException('No pending invitation');

    team.pendingInvites.splice(idx, 1);
    await team.save();
  }

  /** Remove a member from a team (owner only) */
  async removeMember(teamId: string, requesterId: string, targetUserId: string): Promise<void> {
    const team = await this.teamModel.findById(teamId);
    if (!team) throw new NotFoundException('Team not found');
    if (team.ownerId !== requesterId) throw new ForbiddenException('Only the team owner can remove members');
    if (targetUserId === team.ownerId) throw new BadRequestException('Cannot remove the owner');

    team.members = team.members.filter((m) => m !== targetUserId);
    await team.save();
  }

  /** Leave a team */
  async leave(teamId: string, userId: string): Promise<void> {
    const team = await this.teamModel.findById(teamId);
    if (!team) throw new NotFoundException('Team not found');
    if (userId === team.ownerId) throw new BadRequestException('Owner cannot leave. Delete the team instead.');

    team.members = team.members.filter((m) => m !== userId);
    await team.save();
  }

  /** Delete a team (owner only) */
  async deleteTeam(teamId: string, requesterId: string): Promise<void> {
    const team = await this.teamModel.findById(teamId);
    if (!team) throw new NotFoundException('Team not found');
    if (team.ownerId !== requesterId) throw new ForbiddenException('Only the team owner can delete');
    await this.teamModel.findByIdAndDelete(teamId);
  }

  /** Get all teammates of a user (union of all teams they belong to) */
  async getTeammates(userId: string): Promise<string[]> {
    const teams = await this.teamModel.find({ members: userId }).lean();
    const set = new Set<string>();
    for (const t of teams) {
      for (const m of t.members) {
        if (m !== userId) set.add(m);
      }
    }
    return Array.from(set);
  }

  /** Check if two users share at least one team */
  async areTeammates(userId1: string, userId2: string): Promise<boolean> {
    const count = await this.teamModel.countDocuments({
      members: { $all: [userId1, userId2] },
    });
    return count > 0;
  }

  /** Search players by name for invite (excluding existing members/invites) */
  async searchPlayersForInvite(teamId: string, query: string): Promise<any[]> {
    const team = await this.teamModel.findById(teamId).lean();
    if (!team) throw new NotFoundException('Team not found');

    const excludeIds = [...team.members, ...team.pendingInvites];
    // Use users service to get all players, then filter
    const allPlayers = await this.usersSvc.listPlayers();
    const q = (query || '').toLowerCase();
    return allPlayers.filter((p: any) => {
      const id = (p._id || '').toString();
      if (excludeIds.includes(id)) return false;
      if (!q) return true;
      const name = (p.displayName || '').toLowerCase();
      const email = (p.email || '').toLowerCase();
      return name.includes(q) || email.includes(q);
    });
  }
}
