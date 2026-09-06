import { Body, Controller, Get, NotFoundException, Param, ParseUUIDPipe, Patch, Post, UseGuards, UseInterceptors } from '@nestjs/common';
import { JwtAuthGuard } from '../../../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../../../common/guards/roles.guard';
import { Roles } from '../../../../common/decorators/roles.decorator';
import { AuditAction, AuditInterceptor } from '../../../../common/interceptors/audit.interceptor';
import { CreateUniteOperationnelleDto, ReferentielOrganisationDto } from '../dto/org.dto';
import {
  CreateUniteOperationnelleUseCase,
  ListUnitesByOrganisationUseCase,
  SetUniteOperationnelleActivationUseCase,
  UpdateUniteOperationnelleReferentielUseCase,
} from '../../../application/use-cases/unite-operationnelle.use-cases';
import { OrganisationNotFoundError, UniteOperationnelleNotFoundError } from '../../../domain/exceptions/org.exceptions';

@Controller({ path: 'org/unites-operationnelles', version: '1' })
@UseGuards(JwtAuthGuard, RolesGuard)
@UseInterceptors(AuditInterceptor)
export class UniteOperationnelleController {
  constructor(
    private readonly createUniteOperationnelleUseCase: CreateUniteOperationnelleUseCase,
    private readonly updateUniteOperationnelleReferentielUseCase: UpdateUniteOperationnelleReferentielUseCase,
    private readonly listUnitesByOrganisationUseCase: ListUnitesByOrganisationUseCase,
    private readonly setUniteOperationnelleActivationUseCase: SetUniteOperationnelleActivationUseCase,
  ) {}

  @Get('par-organisation/:organisationId')
  @Roles('kernel.admin', 'org.owner')
  async listByOrganisation(@Param('organisationId', ParseUUIDPipe) organisationId: string) {
    try {
      const unites = await this.listUnitesByOrganisationUseCase.execute(organisationId);
      return unites.map((u) => u.toSnapshot());
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post()
  @Roles('kernel.admin', 'org.owner')
  @AuditAction('unite_operationnelle.created')
  async create(@Body() dto: CreateUniteOperationnelleDto) {
    try {
      return await this.createUniteOperationnelleUseCase.execute({
        organisationId: dto.organisationId,
        nom: dto.nom,
        referentiel: {
          paysId: dto.referentiel.paysId ?? null,
          uniteAdministrativeId: dto.referentiel.uniteAdministrativeId ?? null,
          villeId: dto.referentiel.villeId ?? null,
          deviseId: dto.referentiel.deviseId ?? null,
          langueId: dto.referentiel.langueId ?? null,
          fuseauHoraire: dto.referentiel.fuseauHoraire ?? null,
        },
      });
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Patch(':id/referentiel')
  @Roles('kernel.admin', 'org.owner')
  @AuditAction('unite_operationnelle.referentiel_updated')
  async updateReferentiel(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReferentielOrganisationDto,
  ): Promise<{ success: true }> {
    try {
      await this.updateUniteOperationnelleReferentielUseCase.execute(id, {
        paysId: dto.paysId ?? null,
        uniteAdministrativeId: dto.uniteAdministrativeId ?? null,
        villeId: dto.villeId ?? null,
        deviseId: dto.deviseId ?? null,
        langueId: dto.langueId ?? null,
        fuseauHoraire: dto.fuseauHoraire ?? null,
      });
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/deactivate')
  @Roles('kernel.admin', 'org.owner')
  async deactivate(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.setUniteOperationnelleActivationUseCase.deactivate(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/reactivate')
  @Roles('kernel.admin', 'org.owner')
  async reactivate(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.setUniteOperationnelleActivationUseCase.reactivate(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  private mapDomainError(error: unknown): unknown {
    if (error instanceof OrganisationNotFoundError || error instanceof UniteOperationnelleNotFoundError) {
      return new NotFoundException(error.message);
    }
    return error;
  }
}
