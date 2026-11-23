import { Type } from 'class-transformer';
import {
  ArrayMaxSize, IsBoolean, IsDateString, IsEnum, IsInt, IsOptional, IsString, IsUrl, IsUUID, Length, Max, Min, ValidateIf,
} from 'class-validator';
import { ApplicationStage, JobStatus, JobType } from '@prisma/client';

export class EmployerDto {
  @IsString() @Length(2, 120) companyName: string;
  @IsOptional() @IsUrl() website?: string;
  @IsOptional() @IsString() @Length(0, 2000) about?: string;
  @IsOptional() @IsString() @Length(0, 120) location?: string;
}

export class JobDto {
  @IsString() @Length(5, 120) title: string;
  @IsString() @Length(50, 8000) description: string;
  @IsString({ each: true }) @Length(1, 40, { each: true }) @ArrayMaxSize(15) skills: string[];
  @IsEnum(JobType) type: JobType;
  @IsOptional() @IsString() @Length(0, 120) location?: string;
  /** Monthly salary range in BDT (optional, both or neither). */
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) @Max(10_000_000) salaryMin?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) @Max(10_000_000) salaryMax?: number;
  @IsOptional() @IsDateString() deadline?: string;
}

export class SeekerDto {
  @IsString() @Length(3, 120) headline: string;
  @IsOptional() @IsString() @Length(0, 4000) about?: string;
  @IsString({ each: true }) @Length(1, 40, { each: true }) @ArrayMaxSize(20) skills: string[];
  @IsOptional() @IsString() @Length(0, 120) location?: string;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID() cvUploadId?: string | null;
  @IsOptional() @ValidateIf((_, v) => v !== null && v !== '') @IsUrl() cvLink?: string | null;
  @IsOptional() @IsBoolean() openToWork?: boolean;
}

export class ApplyJobDto {
  @IsOptional() @IsString() @Length(0, 3000) coverLetter?: string;
}

export class StageDto {
  @IsOptional() @IsEnum(ApplicationStage) stage?: ApplicationStage;
  @IsOptional() @IsString() @Length(0, 2000) note?: string;
}

export class JobQueryDto {
  @IsOptional() @IsString() @Length(0, 100) q?: string;
  @IsOptional() @IsEnum(JobType) type?: JobType;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) page?: number;
}

export class AdminJobQueryDto {
  @IsOptional() @IsEnum(JobStatus) status?: JobStatus;
}

export class RejectDto {
  @IsString() @Length(5, 1000) reason: string;
}

export class VerifyDto {
  @IsBoolean() verified: boolean;
}
