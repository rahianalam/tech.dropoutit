import { IsEmail, IsOptional, IsString, Length, Matches, MinLength, ValidateIf } from 'class-validator';

export class RegisterDto {
  @IsString()
  @Length(2, 80)
  name: string;

  @ValidateIf((o) => !o.phone)
  @IsEmail()
  email?: string;

  /** Bangladeshi mobile, e.g. 01712345678 or +8801712345678 */
  @ValidateIf((o) => !o.email)
  @Matches(/^(?:\+?880|0)1[3-9]\d{8}$/, { message: 'phone must be a valid Bangladeshi mobile number' })
  phone?: string;

  @IsString()
  @MinLength(8)
  password: string;
}

export class LoginDto {
  /** Email or phone */
  @IsString()
  identifier: string;

  @IsString()
  password: string;
}

export class RefreshDto {
  @IsString()
  refreshToken: string;
}

export class UpdateMeDto {
  @IsOptional()
  @IsString()
  @Length(2, 80)
  name?: string;

  @IsOptional()
  @IsString()
  avatarUrl?: string;
}
