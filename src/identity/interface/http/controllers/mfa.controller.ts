import { BadRequestException, Body, Controller, NotFoundException, Post, UnauthorizedException, UseGuards, UseInterceptors } from '@nestjs/common';
import { JwtAuthGuard } from '../../../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../../../common/decorators/roles.decorator';
import { AuthenticatedRequestUser } from '../../../../common/guards/jwt-auth.guard';
import { ConfirmMfaEnrollmentDto } from '../dto/identity.dto';
import {
  ConfirmMfaEnrollmentUseCase,
  StartMfaEnrollmentUseCase,
} from '../../../application/use-cases/mfa.use-cases';
import { AuditAction, AuditInterceptor } from '../../../../common/interceptors/audit.interceptor';
import {
  InvalidMfaCodeError,
  MfaAlreadyEnabledError,
  UserNotFoundError,
} from '../../../domain/exceptions/identity.exceptions';

@Controller({ path: 'mfa', version: '1' })
@UseGuards(JwtAuthGuard)
@UseInterceptors(AuditInterceptor)
export class MfaController {
  constructor(
    private readonly startMfaEnrollmentUseCase: StartMfaEnrollmentUseCase,
    private readonly confirmMfaEnrollmentUseCase: ConfirmMfaEnrollmentUseCase,
  ) {}

  @Post('enroll/start')
  async startEnrollment(@CurrentUser() user: AuthenticatedRequestUser) {
    try {
      return await this.startMfaEnrollmentUseCase.execute(user.gsgId);
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  @Post('enroll/confirm')
  @AuditAction('mfa.enrolled')
  async confirmEnrollment(
    @CurrentUser() user: AuthenticatedRequestUser,
    @Body() dto: ConfirmMfaEnrollmentDto,
  ): Promise<{ success: true }> {
    try {
      await this.confirmMfaEnrollmentUseCase.execute(user.gsgId, dto.factorId, dto.code);
      return { success: true };
    } catch (error) {
      throw this.mapDomainError(error);
    }
  }

  private mapDomainError(error: unknown): unknown {
    if (error instanceof UserNotFoundError) {
      return new NotFoundException(error.message);
    }
    if (error instanceof MfaAlreadyEnabledError) {
      return new BadRequestException(error.message);
    }
    if (error instanceof InvalidMfaCodeError) {
      return new UnauthorizedException(error.message);
    }
    return error;
  }
}
