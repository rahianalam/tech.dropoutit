import { Body, Controller, Delete, Get, HttpCode, Module, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { IsOptional, IsString, IsUUID, Length, Matches } from 'class-validator';
import { Public, Roles } from '../common/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';

class CategoryDto {
  @IsString() @Length(2, 60) name: string;
  @Matches(/^[a-z0-9-]+$/) slug: string;
  @IsOptional() @IsUUID() parentId?: string;
}

@Controller()
export class CategoriesController {
  constructor(private prisma: PrismaService) {}

  @Public() @Get('categories')
  list() {
    return this.prisma.category.findMany({ where: { parentId: null }, orderBy: { name: 'asc' }, include: { children: true } });
  }

  @Roles('ADMIN') @Post('admin/categories')
  create(@Body() dto: CategoryDto) { return this.prisma.category.create({ data: dto }); }

  @Roles('ADMIN') @Delete('admin/categories/:id') @HttpCode(204)
  async remove(@Param('id', ParseUUIDPipe) id: string) { await this.prisma.category.delete({ where: { id } }); }
}

@Module({ controllers: [CategoriesController] })
export class CategoriesModule {}
