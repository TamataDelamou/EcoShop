import { BadRequestException, Body, Controller, NotFoundException, Post, UseGuards, UseInterceptors } from '@nestjs/common';
import { JwtAuthGuard } from '../../../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../../../common/decorators/roles.decorator';
import { AuthenticatedRequestUser } from '../../../../common/guards/jwt-auth.guard';
import { LinkExternalIdentityDto } from '../dto/identity.dto';
import { LinkExternalIdentityUseCase } from '../../../application/use-cases/external-identity-and-profile.use-cases';
import { AuditAction, AuditInterceptor } from '../../../../common/interceptors/audit.interceptor';
import {
  ExternalIdentityAlreadyLinkedError,
  UserNotFoundError,
} from '../../../domain/exceptions/identity.exceptions';

/**
 * KER-ID-02 : un produit déjà en production adopte GSG ID en ajoutant simplement cette
 * correspondance externalUserId ↔ gsgId, sans toucher à son système d'authentification existant.
 */
@Controller({ path: 'external-identities', version: '1' })
@UseGuards(JwtAuthGuard)
@UseInterceptors(AuditInterceptor)
export class ExternalIdentityController {
  constructor(private readonly linkExternalIdentityUseCase: LinkExternalIdentityUseCase) {}

  @Post('link')
  @AuditAction('external_identity.linked')
  async link(
    @CurrentUser() user: AuthenticatedRequestUser,
    @Body() dto: LinkExternalIdentityDto,
  ): Promise<{ success: true }> {
    try {
      await this.linkExternalIdentityUseCase.execute({
        gsgId: user.gsgId,
        produitId: dto.produitId,
        externalUserId: dto.externalUserId,
      });
      return { success: true };
    } catch (error) {
      if (error instanceof UserNotFoundError) {
        throw new NotFoundException(error.message);
      }
      if (error instanceof ExternalIdentityAlreadyLinkedError) {
        throw new BadRequestException(error.message);
      }
      throw error;
    }
  }
}
