import { BadRequestException, Body, Controller, Get, NotFoundException, Param, ParseUUIDPipe, Patch, Post, UseGuards, UseInterceptors } from '@nestjs/common';
import { JwtAuthGuard } from '../../../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../../../common/guards/roles.guard';
import { Roles } from '../../../../common/decorators/roles.decorator';
import { AuditAction, AuditInterceptor } from '../../../../common/interceptors/audit.interceptor';
import { CreateOffreDto, UpdateOffreDto } from '../dto/product.dto';
import {
  CreateOffreUseCase,
  ListOffresByProduitUseCase,
  TransitionOffreWorkflowUseCase,
  UpdateOffreUseCase,
} from '../../../application/use-cases/offre.use-cases';
import { OffreCodeAlreadyExistsError, OffreNotFoundError, ProduitNotFoundError } from '../../../domain/exceptions/product.exceptions';

@Controller({ path: 'product/offres', version: '1' })
@UseGuards(JwtAuthGuard, RolesGuard)
@UseInterceptors(AuditInterceptor)
export class OffreController {
  constructor(
    private readonly createOffreUseCase: CreateOffreUseCase,
    private readonly updateOffreUseCase: UpdateOffreUseCase,
    private readonly transitionOffreWorkflowUseCase: TransitionOffreWorkflowUseCase,
    private readonly listOffresByProduitUseCase: ListOffresByProduitUseCase,
  ) {}

  @Get('par-produit/:produitId')
  @Roles('kernel.admin', 'org.owner')
  async listByProduit(@Param('produitId', ParseUUIDPipe) produitId: string) {
    const offres = await this.listOffresByProduitUseCase.execute(produitId);
    return offres.map((o) => o.toSnapshot());
  }

  @Post()
  @Roles('kernel.admin')
  @AuditAction('offre.created')
  async create(@Body() dto: CreateOffreDto) {
    try {
      return await this.createOffreUseCase.execute(dto);
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Patch(':id')
  @Roles('kernel.admin')
  @AuditAction('offre.updated')
  async update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateOffreDto,
  ): Promise<{ success: true }> {
    try {
      await this.updateOffreUseCase.execute(id, dto);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/workflow/validate')
  @Roles('kernel.admin')
  async validate(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.transitionOffreWorkflowUseCase.validate(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/workflow/reject-to-draft')
  @Roles('kernel.admin')
  async rejectToDraft(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.transitionOffreWorkflowUseCase.rejectToDraft(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/workflow/publish')
  @Roles('kernel.admin')
  @AuditAction('offre.published')
  async publish(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.transitionOffreWorkflowUseCase.publish(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/workflow/archive')
  @Roles('kernel.admin')
  @AuditAction('offre.archived')
  async archive(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.transitionOffreWorkflowUseCase.archive(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  private mapDomainError(error: unknown): unknown {
    if (error instanceof OffreCodeAlreadyExistsError) {
      return new BadRequestException(error.message);
    }
    if (error instanceof ProduitNotFoundError || error instanceof OffreNotFoundError) {
      return new NotFoundException(error.message);
    }
    return error;
  }
}
