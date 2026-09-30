export class ManualPaymentProvider {
  constructor() { this.name = 'manual'; }
  createPayment({ orderNumber, amount }) { return { provider: this.name, reference: `MANUAL-${orderNumber}`, amount, status: 'pending' }; }
  verifyWebhook(payload, signature) { return Boolean(payload?.orderNumber && payload?.status && signature === process.env.PAYMENT_WEBHOOK_SECRET); }
}

export class ManualShippingProvider {
  quote({ quantity = 1, city = '' }) {
    const base = city.toLowerCase().includes('jakarta') ? 18000 : 35000;
    return { method: 'Regular', cost: base + Math.max(0, quantity - 1) * 5000, estimatedDays: '2–5 hari kerja' };
  }
}

export class NotificationService {
  emit(event, payload) {
    console.info(`[notification:${event}]`, JSON.stringify(payload));
  }
}
