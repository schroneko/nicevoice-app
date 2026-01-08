import Stripe from "stripe";

interface Env {
  STRIPE_SECRET_KEY: string;
  STRIPE_WEBHOOK_SECRET: string;
  STRIPE_SUCCESS_URL: string;
  STRIPE_CANCEL_URL: string;
  PORTAL_RETURN_URL: string;
}

interface CheckoutRequest {
  plan: "plus" | "pro";
  interval: "monthly" | "yearly";
  device_id: string;
  customer_id?: string;
}

interface PortalRequest {
  customer_id: string;
}

interface VerifyRequest {
  customer_id: string;
  device_id: string;
}

const PRICE_IDS: Record<string, Record<string, string>> = {
  plus: {
    monthly: "price_plus_monthly",
    yearly: "price_plus_yearly",
  },
  pro: {
    monthly: "price_pro_monthly",
    yearly: "price_pro_yearly",
  },
};

function corsHeaders(): HeadersInit {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };
}

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders(),
    },
  });
}

function errorResponse(message: string, status = 400): Response {
  return jsonResponse({ error: message }, status);
}

async function handleCheckout(request: Request, env: Env): Promise<Response> {
  const body = (await request.json()) as CheckoutRequest;
  const { plan, interval, device_id, customer_id } = body;

  if (!plan || !interval || !device_id) {
    return errorResponse("Missing required fields");
  }

  const priceId = PRICE_IDS[plan]?.[interval];
  if (!priceId) {
    return errorResponse("Invalid plan or interval");
  }

  const stripe = new Stripe(env.STRIPE_SECRET_KEY);

  const sessionParams: Stripe.Checkout.SessionCreateParams = {
    mode: "subscription",
    line_items: [{ price: priceId, quantity: 1 }],
    success_url: `${env.STRIPE_SUCCESS_URL}?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: env.STRIPE_CANCEL_URL,
    metadata: { device_id },
    allow_promotion_codes: true,
  };

  if (customer_id) {
    sessionParams.customer = customer_id;
  } else {
    sessionParams.customer_creation = "always";
  }

  const session = await stripe.checkout.sessions.create(sessionParams);

  return jsonResponse({
    url: session.url,
    sessionId: session.id,
  });
}

async function handlePortal(request: Request, env: Env): Promise<Response> {
  const body = (await request.json()) as PortalRequest;
  const { customer_id } = body;

  if (!customer_id) {
    return errorResponse("Missing customer_id");
  }

  const stripe = new Stripe(env.STRIPE_SECRET_KEY);

  const session = await stripe.billingPortal.sessions.create({
    customer: customer_id,
    return_url: env.PORTAL_RETURN_URL,
  });

  return jsonResponse({ url: session.url });
}

async function handleVerify(request: Request, env: Env): Promise<Response> {
  const body = (await request.json()) as VerifyRequest;
  const { customer_id } = body;

  if (!customer_id) {
    return jsonResponse({
      valid: false,
      plan: "free",
      status: "none",
      current_period_end: null,
      trial_end: null,
      customer_id: null,
      subscription_id: null,
    });
  }

  const stripe = new Stripe(env.STRIPE_SECRET_KEY);

  const subscriptions = await stripe.subscriptions.list({
    customer: customer_id,
    status: "all",
    limit: 1,
    expand: ["data.items.data.price"],
  });

  const subscription = subscriptions.data[0];

  if (!subscription) {
    return jsonResponse({
      valid: false,
      plan: "free",
      status: "none",
      current_period_end: null,
      trial_end: null,
      customer_id,
      subscription_id: null,
    });
  }

  const priceId = subscription.items.data[0]?.price?.id;
  let plan = "free";

  for (const [planName, prices] of Object.entries(PRICE_IDS)) {
    if (Object.values(prices).includes(priceId || "")) {
      plan = planName;
      break;
    }
  }

  const isActive = ["active", "trialing"].includes(subscription.status);

  return jsonResponse({
    valid: isActive,
    plan,
    status: subscription.status,
    current_period_end: subscription.current_period_end,
    trial_end: subscription.trial_end,
    customer_id,
    subscription_id: subscription.id,
  });
}

async function handleWebhook(request: Request, env: Env): Promise<Response> {
  const signature = request.headers.get("stripe-signature");
  if (!signature) {
    return errorResponse("Missing signature", 400);
  }

  const body = await request.text();
  const stripe = new Stripe(env.STRIPE_SECRET_KEY);

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(body, signature, env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    console.error("Webhook signature verification failed:", err);
    return errorResponse("Invalid signature", 400);
  }

  console.log(`Webhook event: ${event.type}`);

  switch (event.type) {
    case "checkout.session.completed": {
      const session = event.data.object;
      console.log(
        `Checkout completed: customer=${session.customer}, subscription=${session.subscription}`,
      );
      break;
    }
    case "customer.subscription.updated": {
      const subscription = event.data.object;
      console.log(`Subscription updated: ${subscription.id}, status=${subscription.status}`);
      break;
    }
    case "customer.subscription.deleted": {
      const subscription = event.data.object;
      console.log(`Subscription deleted: ${subscription.id}`);
      break;
    }
    case "invoice.payment_failed": {
      const invoice = event.data.object;
      console.log(`Payment failed: invoice=${invoice.id}, customer=${invoice.customer}`);
      break;
    }
  }

  return jsonResponse({ received: true });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders() });
    }

    if (request.method === "POST") {
      try {
        switch (url.pathname) {
          case "/api/checkout":
            return await handleCheckout(request, env);
          case "/api/portal":
            return await handlePortal(request, env);
          case "/api/verify":
            return await handleVerify(request, env);
          case "/api/webhook":
            return await handleWebhook(request, env);
        }
      } catch (err) {
        console.error("API error:", err);
        return errorResponse("Internal server error", 500);
      }
    }

    return new Response(null, { status: 404 });
  },
};
