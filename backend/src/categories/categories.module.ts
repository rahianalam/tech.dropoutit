import { Body, ConflictException, Controller, Delete, Get, HttpCode, Module, Param, ParseUUIDPipe, Patch, Post } from '@nestjs/common';
import { IsHexColor, IsInt, IsOptional, IsString, IsUUID, Length, Matches, Min } from 'class-validator';
import { Public, Roles } from '../common/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';

class CategoryDto {
  @IsString() @Length(2, 60) name: string;
  @Matches(/^[a-z0-9-]+$/) slug: string;
  @IsOptional() @IsUUID() parentId?: string;
  /** Icon name the app knows, e.g. code, phone, brush, campaign, work, translate, analytics, school. */
  @IsOptional() @IsString() @Length(1, 40) icon?: string;
  @IsOptional() @IsHexColor() color?: string;
  @IsOptional() @IsInt() @Min(0) position?: number;
}

class UpdateCategoryDto {
  @IsOptional() @IsString() @Length(2, 60) name?: string;
  @IsOptional() @Matches(/^[a-z0-9-]+$/) slug?: string;
  @IsOptional() @IsString() @Length(1, 40) icon?: string;
  @IsOptional() @IsHexColor() color?: string;
  @IsOptional() @IsInt() @Min(0) position?: number;
}

const order = [{ position: 'asc' as const }, { name: 'asc' as const }];

@Controller()
export class CategoriesController {
  constructor(private prisma: PrismaService) {}

  @Public() @Get('categories')
  async list() {
    const cats = await this.prisma.category.findMany({
      where: { parentId: null },
      orderBy: order,
      include: { children: { orderBy: order }, _count: { select: { courses: { where: { status: 'PUBLISHED' } } } } },
    });
    return cats.map(({ _count, ...c }) => ({ ...c, courseCount: _count.courses }));
  }

  @Roles('ADMIN') @Post('admin/categories')
  create(@Body() dto: CategoryDto) { return this.prisma.category.create({ data: dto }); }

  @Roles('ADMIN') @Patch('admin/categories/:id')
  update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateCategoryDto) {
    return this.prisma.category.update({ where: { id }, data: dto });
  }

  /** Courses in a deleted category simply become uncategorised. */
  @Roles('ADMIN') @Delete('admin/categories/:id') @HttpCode(204)
  async remove(@Param('id', ParseUUIDPipe) id: string) {
    if (await this.prisma.category.count({ where: { parentId: id } })) throw new ConflictException('Delete its sub-categories first');
    await this.prisma.$transaction([
      this.prisma.course.updateMany({ where: { categoryId: id }, data: { categoryId: null } }),
      this.prisma.category.delete({ where: { id } }),
    ]);
  }
}

@Module({ controllers: [CategoriesController] })
export class CategoriesModule {}
