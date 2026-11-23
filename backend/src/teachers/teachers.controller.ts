import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApplicationStatus } from '@prisma/client';
import { AuthUser, CurrentUser, Public, Roles } from '../common/auth.decorators';
import { ApplyDto, ReviewApplicationDto } from './teachers.dto';
import { TeachersService } from './teachers.service';

@Controller()
export class TeachersController {
  constructor(private teachers: TeachersService) {}

  @Post('teacher-applications')
  apply(@CurrentUser() user: AuthUser, @Body() dto: ApplyDto) {
    return this.teachers.apply(user.id, user.roles, dto);
  }

  @Get('teacher-applications/mine')
  mine(@CurrentUser() user: AuthUser) {
    return this.teachers.latestApplication(user.id);
  }

  @Roles('ADMIN')
  @Get('admin/teacher-applications')
  list(@Query('status') status?: ApplicationStatus) {
    return this.teachers.listApplications(status);
  }

  @Roles('ADMIN')
  @Get('admin/teacher-applications/:id')
  get(@Param('id', ParseUUIDPipe) id: string) {
    return this.teachers.getApplication(id);
  }

  @Roles('ADMIN')
  @Post('admin/teacher-applications/:id/review')
  review(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() admin: AuthUser, @Body() dto: ReviewApplicationDto) {
    return this.teachers.review(id, admin.id, dto);
  }

  @Public()
  @Get('teachers')
  all() {
    return this.teachers.list();
  }

  @Public()
  @Get('teachers/:id')
  profile(@Param('id', ParseUUIDPipe) id: string) {
    return this.teachers.publicProfile(id);
  }
}
