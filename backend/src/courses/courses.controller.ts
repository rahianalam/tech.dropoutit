import { Body, Controller, Delete, Get, HttpCode, Param, ParseBoolPipe, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { AuthUser, CurrentUser, Public, Roles } from '../common/auth.decorators';
import { CourseQueryDto, CreateCourseDto, LessonDto, ReviewCourseDto, SectionDto, UpdateCourseDto, UpdateLessonDto } from './courses.dto';
import { CoursesService } from './courses.service';

const Id = (name = 'id') => Param(name, ParseUUIDPipe);

@Controller()
export class CoursesController {
  constructor(private courses: CoursesService) {}

  // public
  @Public() @Get('courses')
  search(@Query() q: CourseQueryDto) { return this.courses.search(q); }

  @Public() @Get('courses/:id')
  detail(@Id() id: string, @CurrentUser() user?: AuthUser) { return this.courses.detail(id, user); }

  @Public() @Get('lessons/:id')
  lesson(@Id() id: string, @CurrentUser() user?: AuthUser) { return this.courses.lessonContent(id, user); }

  // teacher
  @Roles('TEACHER') @Post('teacher/courses')
  create(@CurrentUser() u: AuthUser, @Body() dto: CreateCourseDto) { return this.courses.create(u.id, dto); }

  @Roles('TEACHER') @Get('teacher/courses')
  mine(@CurrentUser() u: AuthUser) { return this.courses.mine(u.id); }

  @Roles('TEACHER', 'ADMIN') @Get('teacher/courses/:id')
  curriculum(@Id() id: string, @CurrentUser() u: AuthUser) { return this.courses.curriculumForOwner(id, u); }

  @Roles('TEACHER', 'ADMIN') @Patch('teacher/courses/:id')
  update(@Id() id: string, @CurrentUser() u: AuthUser, @Body() dto: UpdateCourseDto) { return this.courses.update(id, u, dto); }

  @Roles('TEACHER') @Post('teacher/courses/:id/submit')
  submit(@Id() id: string, @CurrentUser() u: AuthUser) { return this.courses.submitForReview(id, u); }

  @Roles('TEACHER', 'ADMIN') @Post('teacher/courses/:id/sections')
  addSection(@Id() id: string, @CurrentUser() u: AuthUser, @Body() dto: SectionDto) { return this.courses.addSection(id, u, dto); }

  @Roles('TEACHER', 'ADMIN') @Patch('teacher/sections/:id')
  updateSection(@Id() id: string, @CurrentUser() u: AuthUser, @Body() dto: SectionDto) { return this.courses.updateSection(id, u, dto); }

  @Roles('TEACHER', 'ADMIN') @Delete('teacher/sections/:id') @HttpCode(204)
  deleteSection(@Id() id: string, @CurrentUser() u: AuthUser) { return this.courses.deleteSection(id, u); }

  @Roles('TEACHER', 'ADMIN') @Post('teacher/sections/:id/lessons')
  addLesson(@Id() id: string, @CurrentUser() u: AuthUser, @Body() dto: LessonDto) { return this.courses.addLesson(id, u, dto); }

  @Roles('TEACHER', 'ADMIN') @Patch('teacher/lessons/:id')
  updateLesson(@Id() id: string, @CurrentUser() u: AuthUser, @Body() dto: UpdateLessonDto) { return this.courses.updateLesson(id, u, dto); }

  @Roles('TEACHER', 'ADMIN') @Delete('teacher/lessons/:id') @HttpCode(204)
  deleteLesson(@Id() id: string, @CurrentUser() u: AuthUser) { return this.courses.deleteLesson(id, u); }

  // admin
  @Roles('ADMIN') @Get('admin/courses/review-queue')
  queue() { return this.courses.reviewQueue(); }

  @Roles('ADMIN') @Post('admin/courses/:id/review')
  review(@Id() id: string, @CurrentUser() u: AuthUser, @Body() dto: ReviewCourseDto) { return this.courses.review(id, u.id, dto); }

  @Roles('ADMIN') @Post('admin/courses/:id/featured/:on')
  featured(@Id() id: string, @Param('on', ParseBoolPipe) on: boolean) { return this.courses.setFeatured(id, on); }
}
