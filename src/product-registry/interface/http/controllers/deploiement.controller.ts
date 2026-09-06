import { Body, Controller, Get, NotFoundException, Param, ParseUUIDPipe, Post, UseGuards, UseInterceptors } from '@nestjs/common';
import { JwtAuthGuard } from '../../../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../../../common/guards/roles.guard';
import { Roles } from '../../../../common/decorators/roles.decorator';
import { AuditAction, AuditInterceptor } from '../../../../common/interceptors/audit.interceptor';
import { SetDeploiementStatutDto } from '../dto/product-registry.dto';
import {
  ListDeploiementsByProduitUseCase,
  SetDeploiementStatutUseCase,
} from '../../../application/use-cases/deploiement.use-cases';
import { ProduitPortefeuilleNotFoundError } from '../../../domain/exceptions/product-registry.exceptions';

@Controller({ path: 'product-registry/produits/:produitId/deploiements', version: '1' })
export class DeploiementController {
  constructor(
    private readonly setDeploiementStatutUseCase: SetDeploiementStatutUseCase,
    private readonly listDeploiementsByProduitUseCase: ListDeploiementsByProduitUseCase,
  ) {}

  @Get()
  async list(@Param('produitId', ParseUUIDPipe) produitId: string) {
    const deploiements = await this.listDeploiementsByProduitUseCase.execute(produitId);
    return deploiements.map((d) => d.toSnapshot());
  }

  @Post()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('kernel.admin')
  @UseInterceptors(AuditInterceptor)
  @AuditAction('produit_pays_deploiement.set')
  async setStatut(
    @Param('produitId', ParseUUIDPipe) produitId: string,
    @Body() dto: SetDeploiementStatutDto,
  ) {
    try {
      return await this.setDeploiementStatutUseCase.execute({ produitId, ...dto });
    } catch (error) {
      if (error instanceof ProduitPortefeuilleNotFoundError) {
        throw new NotFoundException(error.message);
      }
      throw error;
    }
  }
}
