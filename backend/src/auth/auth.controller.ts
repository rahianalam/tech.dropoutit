import { BadRequestException, Body, Controller, Get, HttpCode, Patch, Post } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { AuthUser, CurrentUser, Public } from '../common/auth.decorators';
import { AccountDeletionService } from './account-deletion.service';
import { ChangeLoginDto, ChangePasswordDto, DeleteAccountDto, LoginDto, RefreshDto, RegisterDto, UpdateMeDto } from './auth.dto';
import { AuthService } from './auth.service';

@Controller('auth')
export class AuthController {
  constructor(
    private auth: AuthService,
    private prisma: PrismaService,
    private deletion: AccountDeletionService,
  ) {}

  @Public()
  @Post('register')
  register(@Body() dto: RegisterDto) {
    return this.auth.register(dto);
  }

  @Public()
  @HttpCode(200)
  @Post('login')
  login(@Body() dto: LoginDto) {
    return this.auth.login(dto);
  }

  @Public()
  @HttpCode(200)
  @Post('refresh')
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }

  @HttpCode(204)
  @Post('logout')
  async logout(@Body() dto: RefreshDto) {
    await this.auth.logout(dto.refreshToken);
  }

  @Get('me')
  async me(@CurrentUser() user: AuthUser) {
    const u = await this.prisma.user.findUniqueOrThrow({
      where: { id: user.id },
      select: { id: true, name: true, email: true, phone: true, avatarUrl: true, createdAt: true, freePassUntil: true },
    });
    const freePassUntil = u.freePassUntil && u.freePassUntil > new Date() ? u.freePassUntil : null;
    return { ...u, freePassUntil, roles: user.roles };
  }

  @Patch('me')
  async updateMe(@CurrentUser() user: AuthUser, @Body() dto: UpdateMeDto) {
    await this.prisma.user.update({ where: { id: user.id }, data: dto });
    return this.me(user);
  }

  @HttpCode(200)
  @Post('change-password')
  changePassword(@CurrentUser() user: AuthUser, @Body() dto: ChangePasswordDto) {
    return this.auth.changePassword(user.id, dto.currentPassword, dto.newPassword);
  }

  /** Change the email/phone used to sign in — this is how the admin changes their login ID. */
  @HttpCode(200)
  @Post('change-login')
  async changeLogin(@CurrentUser() user: AuthUser, @Body() dto: ChangeLoginDto) {
    if (!dto.email && !dto.phone) throw new BadRequestException('Give a new email or phone');
    await this.auth.changeLogin(user.id, dto.password, dto.email, dto.phone);
    return this.me(user);
  }

  /** Permanently deletes the signed-in account (password required). */
  @HttpCode(204)
  @Post('delete-account')
  async deleteAccount(@CurrentUser() user: AuthUser, @Body() dto: DeleteAccountDto) {
    await this.deletion.delete(user.id, dto.password);
  }
}
