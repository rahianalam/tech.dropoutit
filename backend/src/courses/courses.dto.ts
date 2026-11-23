import { Type } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsBoolean, IsEnum, IsIn, IsInt, IsOptional, IsString, IsUUID, Length, Max, Min } from 'class-validator';
import { CourseLevel, LessonType } from '@prisma/client';

export class CreateCourseDto {
  @IsString() @Length(5, 120) title: string;
  @IsOptional() @IsString() @Length(0, 200) subtitle?: string;
  @IsString() @Length(20, 10000) description: string;
  @IsOptional() @IsUUID() categoryId?: string;
  @IsOptional() @IsString() thumbnailUrl?: string;
  /** Price in BDT (whole taka). 0 = free course. */
  @IsInt() @Min(0) @Max(1_000_000) priceBdt: number;
  @IsOptional() @IsEnum(CourseLevel) level?: CourseLevel;
  @IsOptional() @IsIn(['bn', 'en']) language?: string;
  /** Optional "was" price in BDT, shown struck through. */
  @IsOptional() @IsInt() @Min(0) @Max(1_000_000) originalPriceBdt?: number | null;
  @IsOptional() @IsArray() @ArrayMaxSize(20) @IsString({ each: true }) @Length(1, 200, { each: true }) outcomes?: string[];
  @IsOptional() @IsArray() @ArrayMaxSize(20) @IsString({ each: true }) @Length(1, 200, { each: true }) requirements?: string[];
  @IsOptional() @IsArray() @ArrayMaxSize(20) @IsString({ each: true }) @Length(1, 200, { each: true }) audience?: string[];
}

export class UpdateCourseDto {
  @IsOptional() @IsString() @Length(5, 120) title?: string;
  @IsOptional() @IsString() @Length(0, 200) subtitle?: string;
  @IsOptional() @IsString() @Length(20, 10000) description?: string;
  @IsOptional() @IsUUID() categoryId?: string;
  @IsOptional() @IsString() thumbnailUrl?: string;
  @IsOptional() @IsInt() @Min(0) @Max(1_000_000) priceBdt?: number;
  @IsOptional() @IsEnum(CourseLevel) level?: CourseLevel;
  @IsOptional() @IsIn(['bn', 'en']) language?: string;
  /** Optional "was" price in BDT, shown struck through. */
  @IsOptional() @IsInt() @Min(0) @Max(1_000_000) originalPriceBdt?: number | null;
  @IsOptional() @IsArray() @ArrayMaxSize(20) @IsString({ each: true }) @Length(1, 200, { each: true }) outcomes?: string[];
  @IsOptional() @IsArray() @ArrayMaxSize(20) @IsString({ each: true }) @Length(1, 200, { each: true }) requirements?: string[];
  @IsOptional() @IsArray() @ArrayMaxSize(20) @IsString({ each: true }) @Length(1, 200, { each: true }) audience?: string[];
}

export class SectionDto {
  @IsString() @Length(1, 120) title: string;
  @IsOptional() @IsInt() @Min(0) position?: number;
}

export class LessonDto {
  @IsString() @Length(1, 160) title: string;
  @IsOptional() @IsEnum(LessonType) type?: LessonType;
  @IsOptional() @IsString() mediaKey?: string;
  @IsOptional() @IsString() content?: string;
  @IsOptional() @IsInt() @Min(0) durationSec?: number;
  @IsOptional() @IsBoolean() isPreview?: boolean;
  @IsOptional() @IsInt() @Min(0) position?: number;
}

export class UpdateLessonDto {
  @IsOptional() @IsString() @Length(1, 160) title?: string;
  @IsOptional() @IsEnum(LessonType) type?: LessonType;
  @IsOptional() @IsString() mediaKey?: string;
  @IsOptional() @IsString() content?: string;
  @IsOptional() @IsInt() @Min(0) durationSec?: number;
  @IsOptional() @IsBoolean() isPreview?: boolean;
  @IsOptional() @IsInt() @Min(0) position?: number;
}

export class ReviewCourseDto {
  @IsIn(['PUBLISHED', 'REJECTED']) decision: 'PUBLISHED' | 'REJECTED';
  @IsOptional() @IsString() @Length(0, 2000) note?: string;
}

export class CourseQueryDto {
  @IsOptional() @IsString() q?: string;
  @IsOptional() @IsString() category?: string;
  @IsOptional() @IsIn(['true', 'false']) free?: string;
  @IsOptional() @IsEnum(CourseLevel) level?: CourseLevel;
  @IsOptional() @IsIn(['relevance', 'newest', 'rating', 'price_asc', 'price_desc']) sort?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) page?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(50) pageSize?: number;
}

export class CourseStatusDto {
  /** PUBLISHED puts a course live, DRAFT takes it down (the teacher sees the note). */
  @IsIn(['PUBLISHED', 'DRAFT']) status: 'PUBLISHED' | 'DRAFT';
  @IsOptional() @IsString() @Length(0, 2000) note?: string;
}

export class AdminCourseQueryDto {
  @IsOptional() @IsString() q?: string;
  @IsOptional() @IsIn(['DRAFT', 'IN_REVIEW', 'PUBLISHED', 'REJECTED']) status?: 'DRAFT' | 'IN_REVIEW' | 'PUBLISHED' | 'REJECTED';
}
