import { Module } from '@nestjs/common';
import { UploadsModule } from '../uploads/uploads.module';
import { AccountDeletionService } from './account-deletion.service';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';

@Module({ imports: [UploadsModule], controllers: [AuthController], providers: [AuthService, AccountDeletionService] })
export class AuthModule {}
