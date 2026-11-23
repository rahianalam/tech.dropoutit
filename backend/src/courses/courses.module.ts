import { Module } from '@nestjs/common';
import { CoursesController } from './courses.controller';
import { CoursesService } from './courses.service';
import { MediaService } from './media.service';

@Module({ controllers: [CoursesController], providers: [CoursesService, MediaService], exports: [CoursesService] })
export class CoursesModule {}
