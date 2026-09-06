import { BadRequestException, Body, Controller, Get, NotFoundException, Param, ParseUUIDPipe, Post, Query, UseGuards, UseInterceptors } from '@nestjs/common';
import { JwtAuthGuard } from '../../../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../../../common/guards/roles.guard';
import { Roles } from '../../../../common/decorators/roles.decorator';
import { AuditAction, AuditInterceptor } from '../../../../common/interceptors/audit.interceptor';
import { AttachEntitlementDto, CreateFeatureDto } from '../dto/product.dto';
import {
  AttachEntitlementToOffreUseCase,
  CreateFeatureUseCase,
  ListEntitlementsByOffreUseCase,
  ListFeaturesUseCase,
} from '../../../application/use-cases/feature.use-cases';
import {
  EntitlementAlreadyExistsError,
  FeatureCodeAlreadyExistsError,
  FeatureNotFoundError,
  OffreNotFoundError,
} from '../../../domain/exceptions/product.exceptions';

@Controller({ path: 'product/features', version: '1' })
@UseGuards(JwtAuthGuard, RolesGuard)
@UseInterceptors(AuditInterceptor)
export class FeatureController {
  constructor(
    private readonly createFeatureUseCase: CreateFeatureUseCase,
    private readonly listFeaturesUseCase: ListFeaturesUseCase,
    private readonly attachEntitlementToOffreUseCase: AttachEntitlementToOffreUseCase,
    private readonly listEntitlementsByOffreUseCase: ListEntitlementsByOffreUseCase,
  ) {}

  @Get()
  @Roles('kernel.admin', 'org.owner')
  async list(@Query('includeInactives') includeInactives?: string) {
    const features = await this.listFeaturesUseCase.execute({
      includeInactives: includeInactives === 'true',
    });
    return features.map((f) => f.toSnapshot());
  }

  @Post()
  @Roles('kernel.admin')
  @AuditAction('feature.created')
  async create(@Body() dto: CreateFeatureDto) {
    try {
      return await this.createFeatureUseCase.execute(dto);
    } catch (error) {
      if (error instanceof FeatureCodeAlreadyExistsError) {
        throw new BadRequestException(error.message);
      }
      throw error;
    }
  }

  @Get('entitlements/par-offre/:offreId')
  @Roles('kernel.admin', 'org.owner')
  async listEntitlementsByOffre(@Param('offreId', ParseUUIDPipe) offreId: string) {
    const entitlements = await this.listEntitlementsByOffreUseCase.execute(offreId);
    return entitlements.map((e) => e.toSnapshot());
  }

  @Post('entitlements/par-offre/:offreId')
  @Roles('kernel.admin')
  @AuditAction('entitlement.attached')
  async attachEntitlement(
    @Param('offreId', ParseUUIDPipe) offreId: string,
    @Body() dto: AttachEntitlementDto,
  ) {
    try {
      return await this.attachEntitlementToOffreUseCase.execute({
        offreId,
        featureId: dto.featureId,
        limite: dto.limite ?? null,
        unite: dto.unite,
      });
    } catch (error) {
      if (error instanceof EntitlementAlreadyExistsError) {
        throw new BadRequestException(error.message);
      }
      if (error instanceof OffreNotFoundError || error instanceof FeatureNotFoundError) {
        throw new NotFoundException(error.message);
      }
      throw error;
    }
  }
}
