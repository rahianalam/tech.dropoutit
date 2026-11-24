import { Controller, Get, Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { JwtModule } from '@nestjs/jwt';
import { ScheduleModule } from '@nestjs/schedule';
import { AdminModule } from './admin/admin.module';
import { AuthModule } from './auth/auth.module';
import { CategoriesModule } from './categories/categories.module';
import { AuthGuard } from './common/auth.guard';
import { Public } from './common/auth.decorators';
import { CoursesModule } from './courses/courses.module';
import { EnrollmentsModule } from './enrollments/enrollments.module';
import { PrismaModule } from './prisma/prisma.module';
import { SettingsModule } from './settings/settings.module';
import { TeachersModule } from './teachers/teachers.module';
import { NotificationsModule } from './users/notifications.module';
import { PaymentsModule } from './payments/payments.module';
import { PayoutsModule } from './payouts/payouts.module';
import { JobsModule } from './jobs/jobs.module';
import { PushModule } from './push/push.module';
import { LegalModule } from './legal/legal.module';
import { UploadsModule } from './uploads/uploads.module';
import { BookingsModule } from './bookings/bookings.module';
import { StorageModule } from './storage/storage';

@Controller()
class HealthController {
  @Public() @Get('health') health() { return { ok: true }; }
}

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    JwtModule.register({ global: true }),
    ScheduleModule.forRoot(),
    PrismaModule,
    StorageModule,
    AuthModule,
    TeachersModule,
    CategoriesModule,
    CoursesModule,
    EnrollmentsModule,
    SettingsModule,
    AdminModule,
    NotificationsModule,
    PaymentsModule,
    PayoutsModule,
    BookingsModule,
    UploadsModule,
    JobsModule,
    PushModule,
    LegalModule,
  ],
  controllers: [HealthController],
  providers: [{ provide: APP_GUARD, useClass: AuthGuard }],
})
export class AppModule {}
