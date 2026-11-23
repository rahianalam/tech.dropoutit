import { Body, Controller, Get, Module, Param, ParseUUIDPipe, Patch, Post } from '@nestjs/common';
import { StoragePlan } from '@prisma/client';
import { ArrayMaxSize, IsBoolean, IsEnum, IsIn, IsInt, IsOptional, IsString, Length, Max, Min } from 'class-validator';
import { AuthUser, CurrentUser, Public, Roles } from '../common/auth.decorators';
import { PaymentsModule } from '../payments/payments.module';
import { InstructorService } from './instructor.service';

class ProfileDto {
  @IsOptional() @IsString() @Length(5, 120) headline?: string;
  @IsOptional() @IsString() @Length(30, 4000) bio?: string;
  @IsOptional() @IsString({ each: true }) @ArrayMaxSize(15) skills?: string[];
  @IsOptional() @IsString() @Length(0, 4000) experience?: string;
  @IsOptional() @IsString({ each: true }) @ArrayMaxSize(15) expertise?: string[];
  /** Price for one hour of 1:1; slots of other lengths are priced from it */
  @IsOptional() @IsInt() @Min(0) @Max(100000) hourlyRateBdt?: number;
}
class VerifyDto {
  @IsBoolean() verified: boolean;
}
class PlanDto {
  @IsEnum(StoragePlan) plan: StoragePlan;
  @IsIn([1, 12]) months: 1 | 12;
}

@Controller()
export class InstructorController {
  constructor(private instructor: InstructorService) {}

  @Public() @Get('instructor-rules')
  rules() { return this.instructor.rules(); }

  @Roles('TEACHER', 'ADMIN') @Get('teacher/status')
  status(@CurrentUser() u: AuthUser) { return this.instructor.status(u.id); }

  @Roles('TEACHER') @Patch('teacher/profile')
  profile(@CurrentUser() u: AuthUser, @Body() dto: ProfileDto) { return this.instructor.updateProfile(u.id, dto); }

  @Roles('TEACHER') @Post('teacher/storage-plan')
  buy(@CurrentUser() u: AuthUser, @Body() dto: PlanDto) { return this.instructor.buyPlan(u.id, dto.plan, dto.months); }

  @Roles('ADMIN') @Post('admin/teachers/:id/verify')
  verify(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser, @Body() dto: VerifyDto) { return this.instructor.setVerified(id, u.id, dto.verified); }

  @Roles('TEACHER') @Get('teacher/earnings/breakdown')
  earnings(@CurrentUser() u: AuthUser) { return this.instructor.earnings(u.id); }
}

@Module({ imports: [PaymentsModule], controllers: [InstructorController], providers: [InstructorService], exports: [InstructorService] })
export class InstructorModule {}
