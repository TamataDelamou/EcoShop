import {
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
import { CreateCorpusVersionneDto, GouvernanceDto, UpdateCorpusVersionneDto } from '../dto/referential-engine.dto';
import {
  ArchiveCorpusUseCase,
  CreateCorpusVersionneUseCase,
  PublishCorpusUseCase,
  QueryCorpusUseCase,
  UpdateCorpusVersionneUseCase,
} from '../../../application/use-cases/corpus-versionne.use-cases';
import { CorpusVersionneNotFoundError } from '../../../domain/exceptions/referential-engine.exceptions';

@Controller({ path: 'referential-engine/corpus', version: '1' })
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('kernel.admin')
export class CorpusVersionneController {
  constructor(
    private readonly createCorpusVersionneUseCase: CreateCorpusVersionneUseCase,
    private readonly updateCorpusVersionneUseCase: UpdateCorpusVersionneUseCase,
    private readonly publishCorpusUseCase: PublishCorpusUseCase,
    private readonly archiveCorpusUseCase: ArchiveCorpusUseCase,
    private readonly queryCorpusUseCase: QueryCorpusUseCase,
  ) {}

  @Get(':id')
  async getById(@Param('id', ParseUUIDPipe) id: string) {
    try {
      const corpus = await this.queryCorpusUseCase.getById(id);
      return corpus.toSnapshot();
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Get()
  async listByPaysEtDomaine(@Query('paysId', ParseUUIDPipe) paysId: string, @Query('codeDomaine') codeDomaine: string) {
    const corpusListe = await this.queryCorpusUseCase.listByPaysEtDomaine(paysId, codeDomaine ?? 'administratif');
    return corpusListe.map((c) => c.toSnapshot());
  }

  @Post()
  @UseInterceptors(AuditInterceptor)
  @AuditAction('corpus_versionne.created')
  async create(@Body() dto: CreateCorpusVersionneDto) {
    return this.createCorpusVersionneUseCase.execute({
      paysId: dto.paysId,
      codeDomaine: dto.codeDomaine ?? 'administratif',
      libelleVersion: dto.libelleVersion,
      organismeCertificateur: dto.organismeCertificateur,
      statutConfiance: dto.statutConfiance,
      source: dto.source,
    });
  }

  @Patch(':id')
  @UseInterceptors(AuditInterceptor)
  @AuditAction('corpus_versionne.updated')
  async update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateCorpusVersionneDto,
  ): Promise<{ success: true }> {
    try {
      await this.updateCorpusVersionneUseCase.updateDetails(id, dto);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Patch(':id/gouvernance')
  @UseInterceptors(AuditInterceptor)
  @AuditAction('corpus_versionne.gouvernance_updated')
  async updateGouvernance(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: GouvernanceDto,
  ): Promise<{ success: true }> {
    try {
      await this.updateCorpusVersionneUseCase.updateGouvernance(id, dto);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/publish')
  @UseInterceptors(AuditInterceptor)
  @AuditAction('corpus_versionne.published')
  async publish(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.publishCorpusUseCase.execute(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post(':id/archive')
  @UseInterceptors(AuditInterceptor)
  @AuditAction('corpus_versionne.archived')
  async archive(@Param('id', ParseUUIDPipe) id: string): Promise<{ success: true }> {
    try {
      await this.archiveCorpusUseCase.execute(id);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  private mapDomainError(error: unknown): unknown {
    if (error instanceof CorpusVersionneNotFoundError) {
      return new NotFoundException(error.message);
    }
    return error;
  }
}
