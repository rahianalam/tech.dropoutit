import { Body, Controller, Delete, Get, HttpCode, Injectable, Module, Param, ParseUUIDPipe, Patch, Post, Put, Query } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { AuthUser, CurrentUser, Public, Roles } from '../common/auth.decorators';
import { UploadsModule } from '../uploads/uploads.module';
import { AdminJobQueryDto, ApplyJobDto, EmployerDto, JobDto, JobQueryDto, RejectDto, SeekerDto, StageDto, VerifyDto } from './jobs.dto';
import { JobsService } from './jobs.service';

const Id = () => Param('id', ParseUUIDPipe);

@Controller()
export class JobsController {
  constructor(private jobs: JobsService) {}

  // public
  @Public() @Get('jobs')
  list(@Query() q: JobQueryDto, @CurrentUser() u?: AuthUser) { return this.jobs.list(q, u); }

  @Public() @Get('jobs/:id')
  detail(@Id() id: string, @CurrentUser() u?: AuthUser) { return this.jobs.detail(id, u); }

  // job seeker (any signed-in user can become one)
  @Get('seeker/profile')
  seeker(@CurrentUser() u: AuthUser) { return this.jobs.seekerProfile(u.id); }

  @Put('seeker/profile')
  saveSeeker(@CurrentUser() u: AuthUser, @Body() dto: SeekerDto) { return this.jobs.upsertSeeker(u.id, dto); }

  @Post('jobs/:id/apply')
  apply(@Id() id: string, @CurrentUser() u: AuthUser, @Body() dto: ApplyJobDto) { return this.jobs.apply(u, id, dto); }

  @Get('me/applications')
  myApplications(@CurrentUser() u: AuthUser) { return this.jobs.myApplications(u); }

  @Delete('me/applications/:id') @HttpCode(204)
  withdraw(@Id() id: string, @CurrentUser() u: AuthUser) { return this.jobs.withdraw(u, id); }

  // employer (any signed-in user can create a company profile)
  @Get('employer/profile')
  employer(@CurrentUser() u: AuthUser) { return this.jobs.employerProfile(u.id); }

  @Put('employer/profile')
  saveEmployer(@CurrentUser() u: AuthUser, @Body() dto: EmployerDto) { return this.jobs.upsertEmployer(u.id, dto); }

  @Roles('EMPLOYER') @Get('employer/jobs')
  myJobs(@CurrentUser() u: AuthUser) { return this.jobs.myJobs(u); }

  @Roles('EMPLOYER') @Post('employer/jobs')
  create(@CurrentUser() u: AuthUser, @Body() dto: JobDto) { return this.jobs.createJob(u, dto); }

  @Roles('EMPLOYER') @Put('employer/jobs/:id')
  update(@Id() id: string, @CurrentUser() u: AuthUser, @Body() dto: JobDto) { return this.jobs.updateJob(u, id, dto); }

  @Roles('EMPLOYER') @Post('employer/jobs/:id/close')
  close(@Id() id: string, @CurrentUser() u: AuthUser) { return this.jobs.closeJob(u, id); }

  @Roles('EMPLOYER') @Get('employer/jobs/:id/applications')
  applicants(@Id() id: string, @CurrentUser() u: AuthUser) { return this.jobs.applicants(u, id); }

  @Roles('EMPLOYER') @Patch('employer/applications/:id')
  stage(@Id() id: string, @CurrentUser() u: AuthUser, @Body() dto: StageDto) { return this.jobs.setStage(u, id, dto); }

  // admin
  @Roles('ADMIN') @Get('admin/jobs')
  adminJobs(@Query() q: AdminJobQueryDto) { return this.jobs.adminJobs(q); }

  @Roles('ADMIN') @Post('admin/jobs/:id/approve')
  approve(@Id() id: string, @CurrentUser() u: AuthUser) { return this.jobs.approve(u, id); }

  @Roles('ADMIN') @Post('admin/jobs/:id/reject')
  reject(@Id() id: string, @CurrentUser() u: AuthUser, @Body() dto: RejectDto) { return this.jobs.reject(u, id, dto.reason); }

  @Roles('ADMIN') @Get('admin/employers')
  employers() { return this.jobs.employers(); }

  @Roles('ADMIN') @Patch('admin/employers/:id')
  verify(@Id() id: string, @CurrentUser() u: AuthUser, @Body() dto: VerifyDto) { return this.jobs.verifyEmployer(u, id, dto.verified); }
}

@Injectable()
export class JobsCron {
  private enabled = process.env.SCHEDULER_DISABLED !== 'true';
  constructor(private jobs: JobsService) {}

  @Cron(CronExpression.EVERY_HOUR)
  async closeExpired() {
    if (this.enabled) await this.jobs.closeExpired();
  }
}

@Module({ imports: [UploadsModule], controllers: [JobsController], providers: [JobsService, JobsCron] })
export class JobsModule {}
