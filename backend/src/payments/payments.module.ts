import { Module } from '@nestjs/common';
import { FakeGateway, PaymentGateway, SslcommerzGateway } from './gateway';
import { PaymentsController } from './payments.controller';
import { PaymentsService } from './payments.service';

@Module({
  controllers: [PaymentsController],
  providers: [
    PaymentsService,
    { provide: PaymentGateway, useClass: process.env.PAYMENT_GATEWAY === 'fake' ? FakeGateway : SslcommerzGateway },
  ],
  exports: [PaymentsService],
})
export class PaymentsModule {}
