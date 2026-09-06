import { BadRequestException, Body, Controller, Get, Param, ParseUUIDPipe, Post, UseGuards, UseInterceptors } from '@nestjs/common';
import { JwtAuthGuard } from '../../../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../../../common/guards/roles.guard';
import { Roles } from '../../../../common/decorators/roles.decorator';
import { AuditAction, AuditInterceptor } from '../../../../common/interceptors/audit.interceptor';
import { CreateNiveauAdministratifDto } from '../dto/referential-engine.dto';
import {
  CreateNiveauAdministratifUseCase,
  ListNiveauxAdministratifsUseCase,
} from '../../../application/use-cases/niveau-administratif.use-cases';
import { NiveauAdministratifRangAlreadyExistsError } from '../../../domain/exceptions/referential-engine.exceptions';

@Controller({ path: 'referential-engine/niveaux-administratifs', version: '1' })
export class NiveauAdministratifController {
  constructor(
    private readonly createNiveauAdministratifUseCase: CreateNiveauAdministratifUseCase,
    private readonly listNiveauxAdministratifsUseCase: ListNiveauxAdministratifsUseCase,
  ) {}

  @Get('par-pays/:paysId')
  async listByPays(@Param('paysId', ParseUUIDPipe) paysId: string) {
    const niveaux = await this.listNiveauxAdministratifsUseCase.execute(paysId);
    return niveaux.map((n) => n.toSnapshot());
  }

  @Post()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('kernel.admin')
  @UseInterceptors(AuditInterceptor)
  @AuditAction('niveau_administratif.created')
  async create(@Body() dto: CreateNiveauAdministratifDto) {
    try {
      return await this.createNiveauAdministratifUseCase.execute(dto);
    } catch (error) {
      if (error instanceof NiveauAdministratifRangAlreadyExistsError) {
        throw new BadRequestException(error.message);
      }
      throw error;
    }
  }
}
