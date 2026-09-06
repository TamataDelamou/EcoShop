import { BadRequestException, Body, Controller, Get, NotFoundException, Param, ParseUUIDPipe, Patch, Post, Query, UseGuards, UseInterceptors } from '@nestjs/common';
import { JwtAuthGuard } from '../../../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../../../common/guards/roles.guard';
import { Roles } from '../../../../common/decorators/roles.decorator';
import { AuditAction, AuditInterceptor } from '../../../../common/interceptors/audit.interceptor';
import { BriqueNoyau } from '../../../domain/entities/produit-portefeuille.entity';
import {
  CreateProduitPortefeuilleDto,
  DeclareBriquesDto,
  UpdateProduitPortefeuilleDto,
} from '../dto/product-registry.dto';
import {
  CreateProduitPortefeuilleUseCase,
  GetProduitPortefeuilleUseCase,
  ListProduitsPortefeuilleUseCase,
  SetProduitPortefeuilleActivationUseCase,
  UpdateProduitPortefeuilleUseCase,
} from '../../../application/use-cases/produit-portefeuille.use-cases';
import {
  ProduitPortefeuilleCodeAlreadyExistsError,
  ProduitPortefeuilleNotFoundError,
} from '../../../domain/exceptions/product-registry.exceptions';

@Controller({ path: 'product-registry/produits', version: '1' })
export class ProduitPortefeuilleController {
  constructor(
    private readonly createProduitPortefeuilleUseCase: CreateProduitPortefeuilleUseCase,
    private readonly updateProduitPortefeuilleUseCase: UpdateProduitPortefeuilleUseCase,
    private readonly setProduitPortefeuilleActivationUseCase: SetProduitPortefeuilleActivationUseCase,
    private readonly getProduitPortefeuilleUseCase: GetProduitPortefeuilleUseCase,
    private readonly listProduitsPortefeuilleUseCase: ListProduitsPortefeuilleUseCase,
  ) {}

  @Get()
  async list(@Query('includeInactifs') includeInactifs?: string) {
    const produits = await this.listProduitsPortefeuilleUseCase.execute({
      includeInactifs: includeInactifs === 'true',
    });
    return produits.map((p) => p.toSnapshot());
  }

  @Get(':id')
  async getById(@Param('id', ParseUUIDPipe) id: string) {
    try {
      const produit = await this.getProduitPortefeuilleUseCase.execute(id);
      return produit.toSnapshot();
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('kernel.admin')
  @UseInterceptors(AuditInterceptor)
  @AuditAction('produit_portefeuille.created')
  async create(@Body() dto: CreateProduitPortefeuilleDto) {
    try {
      return await this.createProduitPortefeuilleUseCase.execute({
        code: dto.code,
        nom: dto.nom,
        briquesConsommees: dto.briquesConsommees as BriqueNoyau[] | undefined,
      });
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Patch(':id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('kernel.admin')
  @UseInterceptors(AuditInterceptor)
  @AuditAction('produit_portefeuille.updated')
  async update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateProduitPortefeuilleDto,
  ): Promise<{ success: true }> {
    try {
      await this.updateProduitPortefeuilleUseCase.updateDetails(id, dto);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Patch(':id/briques-consommees')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('kernel.admin')
  @UseInterceptors(AuditInterceptor)
  @AuditAction('produit_portefeuille.briques_updated')
  async declareBriques(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: DeclareBriquesDto,
  ): Promise<{ success: true }> {
    try {
      await this.updateProduitPortefeuilleUseCase.declareBriquesConsommees(
        id,
        dto.briquesConsommees as BriqueNoyau[],
      );
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/deactivate')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('kernel.admin')
  @UseInterceptors(AuditInterceptor)
  @AuditAction('produit_portefeuille.deactivated')
  async deactivate(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.setProduitPortefeuilleActivationUseCase.deactivate(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/reactivate')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('kernel.admin')
  async reactivate(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.setProduitPortefeuilleActivationUseCase.reactivate(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  private mapDomainError(error: unknown): unknown {
    if (error instanceof ProduitPortefeuilleCodeAlreadyExistsError) {
      return new BadRequestException(error.message);
    }
    if (error instanceof ProduitPortefeuilleNotFoundError) {
      return new NotFoundException(error.message);
    }
    return error;
  }
}
