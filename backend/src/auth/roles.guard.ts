import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';

import { ROLES_KEY, Role } from './roles.decorator';
import type { RequestUser } from './request-user';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const roles = this.reflector.getAllAndOverride<Role[]>(ROLES_KEY, [context.getHandler(), context.getClass()]);
    if (!roles || roles.length === 0) return true;

    const req = context.switchToHttp().getRequest() as { user?: RequestUser };
    const user = req.user;
    if (!user) throw new ForbiddenException('Not authenticated');
    if (!roles.includes(user.role)) throw new ForbiddenException('Insufficient role');
    return true;
  }
}
