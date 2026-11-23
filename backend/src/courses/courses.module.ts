import { Module } from '@nestjs/common';
import { UploadsModule } from '../uploads/uploads.module';
import { CoursesController } from './courses.controller';
import { CoursesService } from './courses.service';
import { MediaService } from './media.service';

@Module({ imports: [UploadsModule], controllers: [CoursesController], providers: [CoursesService, MediaService], exports: [CoursesService] })
export class CoursesModule {}
