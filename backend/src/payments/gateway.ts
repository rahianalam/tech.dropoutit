import { Injectable, Logger } from '@nestjs/common';

export interface CheckoutRequest {
  tranId: string;
  amountPaisa: number;
  productName: string;
  productCategory: string;
  customer: { name: string; email?: string | null; phone?: string | null };
}

export interface Verification {
  valid: boolean;
  tranId: string;
  amountPaisa: number;
  feePaisa: number;
  gatewayRef: string;
  raw: unknown;
}

export abstract class PaymentGateway {
  abstract readonly name: string;
  /** Opens a hosted checkout session and returns the URL the app should open. */
  abstract createCheckout(req: CheckoutRequest): Promise<string>;
  /** Asks the gateway itself whether a payment is real. Never trust the callback body alone. */
  abstract verify(valId: string): Promise<Verification>;
}

const toPaisa = (v: unknown) => Math.round(Number(v) * 100);

/**
 * SSLCommerz hosted checkout (bKash, Nagad, Rocket, cards, net banking).
 * Docs: https://developer.sslcommerz.com/doc/v4/
 * Sandbox base: https://sandbox.sslcommerz.com · Live base: https://securepay.sslcommerz.com
 */
@Injectable()
export class SslcommerzGateway extends PaymentGateway {
  readonly name = 'sslcommerz';
  private log = new Logger('SSLCommerz');
  private base = process.env.SSLCZ_BASE_URL ?? 'https://sandbox.sslcommerz.com';
  private storeId = process.env.SSLCZ_STORE_ID ?? '';
  private storePass = process.env.SSLCZ_STORE_PASSWORD ?? '';
  private publicApi = process.env.PUBLIC_API_URL ?? 'http://localhost:3000/api/v1';

  async createCheckout(req: CheckoutRequest): Promise<string> {
    const cb = (kind: string) => `${this.publicApi}/payments/sslcommerz/${kind}`;
    const form = new URLSearchParams({
      store_id: this.storeId,
      store_passwd: this.storePass,
      total_amount: (req.amountPaisa / 100).toFixed(2),
      currency: 'BDT',
      tran_id: req.tranId,
      success_url: cb('success'),
      fail_url: cb('fail'),
      cancel_url: cb('cancel'),
      ipn_url: cb('ipn'),
      product_name: req.productName.slice(0, 250),
      product_category: req.productCategory,
      product_profile: 'non-physical-goods',
      shipping_method: 'NO',
      num_of_item: '1',
      cus_name: req.customer.name,
      cus_email: req.customer.email ?? 'customer@tech.dropout.it',
      cus_phone: req.customer.phone ?? '01700000000',
      cus_add1: 'Bangladesh',
      cus_city: 'Dhaka',
      cus_country: 'Bangladesh',
    });
    const res = await fetch(`${this.base}/gwprocess/v4/api.php`, { method: 'POST', body: form });
    const body = (await res.json()) as { status?: string; GatewayPageURL?: string; failedreason?: string };
    if (body.status !== 'SUCCESS' || !body.GatewayPageURL) {
      this.log.error(`init failed: ${body.failedreason}`);
      throw new Error(`Payment gateway error: ${body.failedreason ?? 'unknown'}`);
    }
    return body.GatewayPageURL;
  }

  async verify(valId: string): Promise<Verification> {
    const qs = new URLSearchParams({ val_id: valId, store_id: this.storeId, store_passwd: this.storePass, format: 'json' });
    const res = await fetch(`${this.base}/validator/api/validationserverAPI.php?${qs}`);
    const body = (await res.json()) as Record<string, string>;
    const valid = (body.status === 'VALID' || body.status === 'VALIDATED') && body.currency === 'BDT';
    const amountPaisa = toPaisa(body.amount);
    return {
      valid,
      tranId: body.tran_id,
      amountPaisa,
      feePaisa: body.store_amount ? amountPaisa - toPaisa(body.store_amount) : 0,
      gatewayRef: body.bank_tran_id ?? valId,
      raw: body,
    };
  }
}

/**
 * Local stand-in used in tests and development (PAYMENT_GATEWAY=fake).
 * A val_id of `ok:<tranId>:<paisa>` verifies; anything else is rejected.
 */
@Injectable()
export class FakeGateway extends PaymentGateway {
  readonly name = 'fake';
  async createCheckout(req: CheckoutRequest): Promise<string> {
    const api = process.env.PUBLIC_API_URL ?? 'http://localhost:3000/api/v1';
    return `${api}/payments/fake/checkout?tran_id=${req.tranId}&amount=${req.amountPaisa}`;
  }
  async verify(valId: string): Promise<Verification> {
    const [tag, tranId, paisa] = valId.split(':');
    const amountPaisa = Number(paisa);
    return { valid: tag === 'ok', tranId, amountPaisa, feePaisa: Math.round(amountPaisa * 0.02), gatewayRef: valId, raw: { valId } };
  }
}
