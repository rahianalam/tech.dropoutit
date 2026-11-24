import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, Equals, IsEnum, IsIn, IsOptional, IsString, IsUrl, Length, ValidateNested } from 'class-validator';
import { PortfolioType } from '@prisma/client';

export class PortfolioItemDto {
  @IsEnum(PortfolioType)
  type: PortfolioType;

  @IsString()
  @Length(1, 120)
  title: string;

  @IsUrl()
  url: string;
}

export class ApplyDto {
  @IsString()
  @Length(5, 120)
  headline: string;

  @IsString()
  @Length(30, 4000)
  bio: string;

  @IsString({ each: true })
  @ArrayMinSize(1)
  @ArrayMaxSize(15)
  skills: string[];

  @IsString()
  @Length(10, 4000)
  experience: string;

  @IsOptional()
  @IsUrl()
  demoVideoUrl?: string;

  /** The applicant read and accepted the instructor rules (fees, free-first courses, storage). */
  @Equals(true, { message: 'Please accept the instructor rules' })
  acceptRules: boolean;

  @ValidateNested({ each: true })
  @Type(() => PortfolioItemDto)
  @ArrayMinSize(1, { message: 'Add at least one portfolio item' })
  @ArrayMaxSize(20)
  portfolio: PortfolioItemDto[];
}

export class ReviewApplicationDto {
  @IsIn(['APPROVED', 'CHANGES_REQUESTED', 'REJECTED'])
  decision: 'APPROVED' | 'CHANGES_REQUESTED' | 'REJECTED';

  @IsOptional()
  @IsString()
  @Length(0, 2000)
  note?: string;
}
