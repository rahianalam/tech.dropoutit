import { Body, Controller, Get, Header, HttpCode, Param, ParseUUIDPipe, Post, Query, Res } from '@nestjs/common';
import { OrderStatus } from '@prisma/client';
import type { Response } from 'express';
import { AuthUser, CurrentUser, Public, Roles } from '../common/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';
import { PaymentsService } from './payments.service';

/** Shown in the browser after checkout; the app polls the order and closes it. */
function resultPage(ok: boolean, orderId?: string) {
  const title = ok ? 'পেমেন্ট সফল হয়েছে' : 'পেমেন্ট সম্পন্ন হয়নি';
  const note = ok ? 'এখন অ্যাপে ফিরে গিয়ে কোর্স শুরু করুন।' : 'টাকা কাটা হলে কিছুক্ষণের মধ্যে অ্যাপে আপডেট হবে, না হলে আবার চেষ্টা করুন।';
  const back = process.env.APP_RETURN_URL ? `<p><a href="${process.env.APP_RETURN_URL}?order=${orderId ?? ''}">অ্যাপে ফিরে যান</a></p>` : '';
  return `<!doctype html><html lang="bn"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head>
<body style="font-family:sans-serif;text-align:center;padding:48px 16px"><h1 style="font-size:22px">${ok ? '✅' : '⚠️'} ${title}</h1><p>${note}</p>${back}</body></html>`;
}

interface GatewayCallback {
  val_id?: string;
  tran_id?: string;
  status?: string;
}

@Controller()
export class PaymentsController {
  constructor(
    private payments: PaymentsService,
    private prisma: PrismaService,
  ) {}

  @Post('checkout/course/:id')
  checkout(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser, @Query('ref') ref?: string) {
    return this.payments.checkoutCourse(u.id, id, ref);
  }

  @Get('orders/:id')
  order(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    return this.payments.getOrder(id, u.id);
  }

  @Get('me/orders')
  myOrders(@CurrentUser() u: AuthUser) {
    return this.payments.myOrders(u.id);
  }

  // ---- gateway callbacks (public; trust comes from verify(), not from the body) ----

  @Public() @Post('payments/sslcommerz/ipn') @HttpCode(200)
  async ipn(@Body() body: GatewayCallback) {
    const { ok } = await this.payments.handleCallback(body.val_id, body.tran_id);
    return { received: true, ok };
  }

  @Public() @Post('payments/sslcommerz/success') @Header('Content-Type', 'text/html; charset=utf-8')
  async success(@Body() body: GatewayCallback) {
    const { order, ok } = await this.payments.handleCallback(body.val_id, body.tran_id);
    return resultPage(ok, order?.id);
  }

  @Public() @Post(['payments/sslcommerz/fail', 'payments/sslcommerz/cancel']) @Header('Content-Type', 'text/html; charset=utf-8')
  async failed(@Body() body: GatewayCallback) {
    if (body.tran_id) await this.payments.markFailed(body.tran_id);
    return resultPage(false);
  }

  /** Development stand-in for the hosted checkout page (PAYMENT_GATEWAY=fake only). */
  @Public() @Get('payments/fake/checkout')
  fakeCheckout(@Query('tran_id') tranId: string, @Query('amount') amount: string, @Res() res: Response) {
    if (process.env.PAYMENT_GATEWAY !== 'fake') return res.status(404).send();
    const valId = `ok:${encodeURIComponent(tranId)}:${Number(amount)}`;
    res.type('html').send(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<body style="font-family:sans-serif;text-align:center;padding:48px 16px"><h2>টেস্ট পেমেন্ট</h2><p>৳${Number(amount) / 100}</p>
<form method="post" action="../sslcommerz/success"><input type="hidden" name="val_id" value="${valId}"><input type="hidden" name="tran_id" value="${encodeURIComponent(tranId)}"><button style="font-size:18px;padding:12px 32px">Pay</button></form>
<form method="post" action="../sslcommerz/cancel"><input type="hidden" name="tran_id" value="${encodeURIComponent(tranId)}"><button>Cancel</button></form></body>`);
  }

  // ---- admin ----

  @Roles('ADMIN') @Get('admin/orders')
  adminOrders(@Query('status') status?: OrderStatus) {
    return this.prisma.order.findMany({
      where: status ? { status } : {},
      orderBy: { createdAt: 'desc' },
      take: 100,
      include: { user: { select: { id: true, name: true, email: true, phone: true } }, payments: { select: { gateway: true, gatewayRef: true, feePaisa: true } } },
    });
  }

  @Roles('ADMIN') @Post('admin/orders/:id/refund')
  refund(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    return this.payments.refund(id, u.id);
  }
}
