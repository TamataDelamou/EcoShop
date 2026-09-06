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
import { CreatePaysDto, UpdatePaysDto } from '../dto/referential.dto';
import {
  CreatePaysUseCase,
  GetPaysUseCase,
  ListPaysUseCase,
  SetPaysActivationUseCase,
  TransitionPaysWorkflowUseCase,
  UpdatePaysUseCase,
} from '../../../application/use-cases/pays.use-cases';
import { PaysCodeIsoAlreadyExistsError, PaysNotFoundError } from '../../../domain/exceptions/referential.exceptions';

/**
 * Lecture publique (données publiées uniquement) : tout produit du portefeuille peut
 * consommer ce référentiel sans authentification renforcée (KER-VIS-03 : API uniquement).
 * Écriture réservée au back-office transversal (KER-ENG-07) : rôle kernel.admin.
 */
@Controller({ path: 'referential/pays', version: '1' })
export class PaysController {
  constructor(
    private readonly createPaysUseCase: CreatePaysUseCase,
    private readonly updatePaysUseCase: UpdatePaysUseCase,
    private readonly transitionPaysWorkflowUseCase: TransitionPaysWorkflowUseCase,
    private readonly setPaysActivationUseCase: SetPaysActivationUseCase,
    private readonly listPaysUseCase: ListPaysUseCase,
    private readonly getPaysUseCase: GetPaysUseCase,
  ) {}

  @Get()
  async list(@Query('includeNonPublies') includeNonPublies?: string) {
    const pays = await this.listPaysUseCase.execute({
      includeNonPublies: includeNonPublies === 'true',
    });
    return pays.map((p) => p.toSnapshot());
  }

  @Get(':id')
  async getById(@Param('id', ParseUUIDPipe) id: string) {
    try {
      const pays = await this.getPaysUseCase.execute(id);
      return pays.toSnapshot();
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('kernel.admin')
  @UseInterceptors(AuditInterceptor)
  @AuditAction('pays.created')
  async create(@Body() dto: CreatePaysDto) {
    try {
      return await this.createPaysUseCase.execute(dto);
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Patch(':id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('kernel.admin')
  @UseInterceptors(AuditInterceptor)
  @AuditAction('pays.updated')
  async update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdatePaysDto): Promise<{ success: true }> {
    try {
      await this.updatePaysUseCase.execute(id, dto);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/workflow/submit-for-review')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('kernel.admin')
  async submitForReview(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.transitionPaysWorkflowUseCase.submitForReview(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/workflow/validate')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('kernel.admin')
  async validate(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.transitionPaysWorkflowUseCase.validate(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/workflow/reject-to-draft')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('kernel.admin')
  async rejectToDraft(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.transitionPaysWorkflowUseCase.rejectToDraft(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/workflow/publish')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('kernel.admin')
  @UseInterceptors(AuditInterceptor)
  @AuditAction('pays.published')
  async publish(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.transitionPaysWorkflowUseCase.publish(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/deactivate')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('kernel.admin')
  @UseInterceptors(AuditInterceptor)
  @AuditAction('pays.deactivated')
  async deactivate(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.setPaysActivationUseCase.deactivate(id);
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
      await this.setPaysActivationUseCase.reactivate(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  private mapDomainError(error: unknown): unknown {
    if (error instanceof PaysCodeIsoAlreadyExistsError) {
      return new BadRequestException(error.message);
    }
    if (error instanceof PaysNotFoundError) {
      return new NotFoundException(error.message);
    }
    return error;
  }
}
