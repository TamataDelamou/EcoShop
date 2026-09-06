import {
  BadRequestException,
  Body,
  Controller,
  Get,
  NotFoundException,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { JwtAuthGuard } from '../../../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../../../common/guards/roles.guard';
import { Roles } from '../../../../common/decorators/roles.decorator';
import { AuditAction, AuditInterceptor } from '../../../../common/interceptors/audit.interceptor';
import {
  CreateOrganisationDto,
  ReattachOrganisationDto,
  UpdateOrganisationDto,
} from '../dto/org.dto';
import {
  CreateOrganisationUseCase,
  GetOrganisationUseCase,
  ListFilialesUseCase,
  ListOrganisationsUseCase,
  ReattachOrganisationUseCase,
  SetOrganisationActivationUseCase,
  UpdateOrganisationReferentielUseCase,
  UpdateOrganisationUseCase,
} from '../../../application/use-cases/organisation.use-cases';
import { ReferentielOrganisationDto } from '../dto/org.dto';
import { CircularParentingError, OrganisationNotFoundError } from '../../../domain/exceptions/org.exceptions';

/**
 * Écriture réservée à kernel.admin (création/désactivation) ; un propriétaire d'organisation
 * (org.owner) peut gérer le référentiel et les détails de SA PROPRE organisation — le contrôle
 * de portée exact est appliqué au niveau use-case/service consommateur, cette API expose les
 * opérations, la vérification d'appartenance métier fine reste du ressort du produit appelant.
 */
@Controller({ path: 'org/organisations', version: '1' })
@UseGuards(JwtAuthGuard, RolesGuard)
@UseInterceptors(AuditInterceptor)
export class OrganisationController {
  constructor(
    private readonly createOrganisationUseCase: CreateOrganisationUseCase,
    private readonly updateOrganisationUseCase: UpdateOrganisationUseCase,
    private readonly updateOrganisationReferentielUseCase: UpdateOrganisationReferentielUseCase,
    private readonly reattachOrganisationUseCase: ReattachOrganisationUseCase,
    private readonly setOrganisationActivationUseCase: SetOrganisationActivationUseCase,
    private readonly getOrganisationUseCase: GetOrganisationUseCase,
    private readonly listOrganisationsUseCase: ListOrganisationsUseCase,
    private readonly listFilialesUseCase: ListFilialesUseCase,
  ) {}

  @Get()
  @Roles('kernel.admin')
  async list(@Query('includeInactives') includeInactives?: string) {
    const organisations = await this.listOrganisationsUseCase.execute({
      includeInactives: includeInactives === 'true',
    });
    return organisations.map((o) => o.toSnapshot());
  }

  @Get(':id')
  @Roles('kernel.admin', 'org.owner')
  async getById(@Param('id', ParseUUIDPipe) id: string) {
    try {
      const organisation = await this.getOrganisationUseCase.execute(id);
      return organisation.toSnapshot();
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Get(':id/filiales')
  @Roles('kernel.admin', 'org.owner')
  async listFiliales(@Param('id', ParseUUIDPipe) id: string) {
    try {
      const filiales = await this.listFilialesUseCase.execute(id);
      return filiales.map((f) => f.toSnapshot());
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post()
  @Roles('kernel.admin')
  @AuditAction('organisation.created')
  async create(@Body() dto: CreateOrganisationDto) {
    try {
      return await this.createOrganisationUseCase.execute({
        nom: dto.nom,
        organisationMereId: dto.organisationMereId ?? null,
        referentiel: this.toReferentiel(dto.referentiel),
      });
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Patch(':id')
  @Roles('kernel.admin', 'org.owner')
  @AuditAction('organisation.updated')
  async update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateOrganisationDto,
  ): Promise<{ success: true }> {
    try {
      await this.updateOrganisationUseCase.execute(id, dto);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Patch(':id/referentiel')
  @Roles('kernel.admin', 'org.owner')
  @AuditAction('organisation.referentiel_updated')
  async updateReferentiel(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReferentielOrganisationDto,
  ): Promise<{ success: true }> {
    try {
      await this.updateOrganisationReferentielUseCase.execute(id, this.toReferentiel(dto));
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/reattach')
  @Roles('kernel.admin')
  @AuditAction('organisation.reattached')
  async reattach(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReattachOrganisationDto,
  ): Promise<{ success: true }> {
    try {
      await this.reattachOrganisationUseCase.execute(id, dto.organisationMereId ?? null);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/deactivate')
  @Roles('kernel.admin')
  @AuditAction('organisation.deactivated')
  async deactivate(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.setOrganisationActivationUseCase.deactivate(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/reactivate')
  @Roles('kernel.admin')
  async reactivate(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.setOrganisationActivationUseCase.reactivate(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  private toReferentiel(dto: ReferentielOrganisationDto) {
    return {
      paysId: dto.paysId ?? null,
      uniteAdministrativeId: dto.uniteAdministrativeId ?? null,
      villeId: dto.villeId ?? null,
      deviseId: dto.deviseId ?? null,
      langueId: dto.langueId ?? null,
      fuseauHoraire: dto.fuseauHoraire ?? null,
    };
  }

  private mapDomainError(error: unknown): unknown {
    if (error instanceof OrganisationNotFoundError) {
      return new NotFoundException(error.message);
    }
    if (error instanceof CircularParentingError) {
      return new BadRequestException(error.message);
    }
    return error;
  }
}
