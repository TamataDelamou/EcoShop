import { Body, Controller, Get, NotFoundException, Post, Query, UseGuards, UseInterceptors } from '@nestjs/common';
import { JwtAuthGuard } from '../../../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../../../common/guards/roles.guard';
import { Roles } from '../../../../common/decorators/roles.decorator';
import { AuditAction, AuditInterceptor } from '../../../../common/interceptors/audit.interceptor';
import { ResolveExchangeRateQueryDto, SetTauxChangeDto } from '../dto/referential.dto';
import {
  ResolveExchangeRateUseCase,
  SetTauxChangeUseCase,
} from '../../../application/use-cases/taux-change.use-cases';
import { DeviseNotFoundError, NoValidExchangeRateError } from '../../../domain/exceptions/referential.exceptions';

@Controller({ path: 'referential/taux-change', version: '1' })
export class TauxChangeController {
  constructor(
    private readonly setTauxChangeUseCase: SetTauxChangeUseCase,
    private readonly resolveExchangeRateUseCase: ResolveExchangeRateUseCase,
  ) {}

  /**
   * KER-REF-04 : renvoie une 404 explicite (NoValidExchangeRateError → NotFoundException via
   * mapDomainError ci-dessous) si aucun taux valide n'existe — jamais un taux 1:1 implicite.
   * Le filtre d'exception global (common/filters/http-exception.filter.ts) ne fait AUCUN
   * mapping domaine → HTTP par lui-même : sans ce mapDomainError, cette erreur remontait en
   * 500 générique, jamais en 404 — corrigé lors de la fermeture systématique des contrôleurs
   * sans mapping d'exception (17 sur 29 au moment de l'audit).
   */
  @Get('resolve')
  async resolve(@Query() query: ResolveExchangeRateQueryDto) {
    try {
      const result = await this.resolveExchangeRateUseCase.execute({
        deviseBaseId: query.deviseBaseId,
        deviseCibleId: query.deviseCibleId,
        instant: query.instant ? new Date(query.instant) : undefined,
      });
      return {
        taux: result.taux,
        validDu: result.validDu.toISOString(),
        validAu: result.validAu?.toISOString() ?? null,
        source: result.source,
      };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('kernel.admin')
  @UseInterceptors(AuditInterceptor)
  @AuditAction('taux_change.set')
  async set(@Body() dto: SetTauxChangeDto) {
    try {
      return await this.setTauxChangeUseCase.execute({
        deviseBaseId: dto.deviseBaseId,
        deviseCibleId: dto.deviseCibleId,
        taux: dto.taux,
        validDu: new Date(dto.validDu),
        validAu: dto.validAu ? new Date(dto.validAu) : null,
        source: dto.source,
      });
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  private mapDomainError(error: unknown): unknown {
    if (error instanceof DeviseNotFoundError || error instanceof NoValidExchangeRateError) {
      return new NotFoundException(error.message);
    }
    return error;
  }
}
