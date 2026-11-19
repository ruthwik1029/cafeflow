import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cafeflow-client, cf-turnstile-response",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const appEnv = Deno.env.get("APP_ENV") || "staging";

    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(
        JSON.stringify({ error: "Server configuration missing." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 1. Production Fail-Closed Safety Gate
    if (appEnv === "production") {
      return new Response(
        JSON.stringify({
          error: "Demo session provisioning is strictly disabled in production environments.",
        }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. Client Attestation & IP-Based Abuse Prevention
    const clientIp =
      req.headers.get("cf-connecting-ip") ||
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
      "unknown-origin";

    const turnstileToken = req.headers.get("cf-turnstile-response");
    const turnstileSecret = Deno.env.get("TURNSTILE_SECRET_KEY");
    const nativeClientHeader = req.headers.get("x-cafeflow-client");

    // Security Note: x-cafeflow-client is an informational client hint, NOT cryptographic attestation.
    // Browsers cannot forge or strip Origin/Referer headers during cross-origin fetch;
    // therefore, any request bearing a web browser origin is strictly forbidden from claiming native exemption.
    const hasBrowserOrigin = !!(req.headers.get("origin") || req.headers.get("referer"));
    const isAuthorizedNativeClient =
      (nativeClientHeader === "cafeflow-desktop-demo" ||
       nativeClientHeader === "cafeflow-mobile-demo") &&
      !hasBrowserOrigin;

    // Strict bot attestation: If Turnstile secret is configured and client is not an authorized native client,
    // Turnstile token is mandatory and must be verified (fails closed).
    if (turnstileSecret && !isAuthorizedNativeClient) {
      if (!turnstileToken) {
        return new Response(
          JSON.stringify({ error: "Bot verification challenge is required for web demo access." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      try {
        const verifyRes = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            secret: turnstileSecret,
            response: turnstileToken,
            remoteip: clientIp,
          }),
        });
        const verifyData = await verifyRes.json();
        if (!verifyData.success) {
          return new Response(
            JSON.stringify({ error: "Bot verification challenge failed." }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      } catch (err: any) {
        return new Response(
          JSON.stringify({ error: "Bot verification service unavailable. Please retry." }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // 3. Admin Client Initialization with Private Service Role
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    // 4. Concurrency Guard: Enforce Maximum 50 Simultaneous Active Demo Sessions
    const { count: activeSessionCount, error: countErr } = await adminClient
      .from("demo_sessions")
      .select("*", { count: "exact", head: true })
      .gt("expires_at", new Date().toISOString());

    if (!countErr && activeSessionCount !== null && activeSessionCount >= 50) {
      return new Response(
        JSON.stringify({
          error:
            "Live demo capacity reached (maximum 50 concurrent active sessions). Please try again shortly.",
        }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 5. Server-Side Rate Limiting (Max 5 sessions / hour / IP)
    const { data: limitCheck, error: limitErr } = await adminClient.rpc(
      "check_and_increment_rate_limit",
      {
        p_client_id: clientIp,
        p_action: "DEMO_SESSION_PROVISION",
        p_window_minutes: 60,
        p_max_requests: 5,
      }
    );

    if (limitErr || limitCheck === false) {
      return new Response(
        JSON.stringify({
          error:
            "Demo session rate limit exceeded (maximum 5 sessions per hour). Please try again later.",
        }),
        { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 6. Parse Optional Client Body (Pairing Code & Role)
    let requestedPairingCode: string | null = null;
    let clientRole = "DEMO_OWNER";
    try {
      const body = await req.json();
      if (body?.pairing_code && typeof body.pairing_code === "string") {
        requestedPairingCode = body.pairing_code.trim();
      }
      if (body?.role === "DEMO_STAFF") {
        clientRole = "DEMO_STAFF";
      }
    } catch (_) {
      // Body is optional
    }

    const demoRestaurantId = "a0000000-0000-0000-0000-000000000001";

    // 7. Generate Ephemeral Credentials & User Account in auth.users
    const randomHex = crypto.randomUUID().substring(0, 8);
    const ephemeralEmail = `demo_${Date.now()}_${randomHex}@cafeflow.internal`;
    const ephemeralPassword = crypto.randomUUID();

    const { data: userData, error: userError } = await adminClient.auth.admin.createUser({
      email: ephemeralEmail,
      password: ephemeralPassword,
      email_confirm: true,
      user_metadata: {
        is_demo: true,
        full_name: clientRole === "DEMO_OWNER" ? "Demonstrator (Owner)" : "Demonstrator (Staff)",
        created_at: new Date().toISOString(),
      },
    });

    if (userError || !userData?.user) {
      throw userError || new Error("Failed to create ephemeral user.");
    }

    const userId = userData.user.id;

    // 8. CRITICAL: Insert user profile in public.user_profiles to satisfy foreign key constraints
    const { error: profileError } = await adminClient.from("user_profiles").insert({
      id: userId,
      full_name: clientRole === "DEMO_OWNER" ? "Demonstrator (Owner)" : "Demonstrator (Staff)",
      phone: "+91 99999 00000",
      username: `demo_${Date.now()}_${randomHex}`,
      is_active: true,
    });

    if (profileError) {
      throw profileError;
    }

    // 9. Bind Ephemeral User to Restricted DEMO_OWNER / DEMO_STAFF Role
    const { error: memberError } = await adminClient.from("restaurant_memberships").insert({
      restaurant_id: demoRestaurantId,
      user_id: userId,
      role: clientRole,
      is_active: true,
    });

    if (memberError) {
      throw memberError;
    }

    // 10. Sign In Ephemeral User to Mint Cryptographic Session Tokens
    const { data: sessionData, error: signinError } = await adminClient.auth.signInWithPassword({
      email: ephemeralEmail,
      password: ephemeralPassword,
    });

    if (signinError || !sessionData?.session) {
      throw signinError || new Error("Failed to sign in demo session.");
    }

    // 11. Session Channel Pairing Management
    let demoSessionId = crypto.randomUUID();
    let pairingCode = "";

    if (requestedPairingCode) {
      // If client requests joining an existing demo channel, verify it exists and is active
      const { data: existingSession, error: lookupErr } = await adminClient
        .from("demo_sessions")
        .select("id, pairing_code, expires_at")
        .eq("pairing_code", requestedPairingCode)
        .gt("expires_at", new Date().toISOString())
        .maybeSingle();

      if (!lookupErr && existingSession) {
        demoSessionId = existingSession.id;
        pairingCode = existingSession.pairing_code;
      }
    }

    if (!pairingCode) {
      // Generate unique 6-digit channel pairing code
      pairingCode = Math.floor(100000 + Math.random() * 900000).toString();
      const expiresAt = new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString();

      await adminClient.from("demo_sessions").insert({
        id: demoSessionId,
        user_id: userId,
        restaurant_id: demoRestaurantId,
        role: clientRole,
        pairing_code: pairingCode,
        expires_at: expiresAt,
      });
    }

    // 12. Return Sanitized Session Tokens to Client (Zero Service Secrets)
    return new Response(
      JSON.stringify({
        access_token: sessionData.session.access_token,
        refresh_token: sessionData.session.refresh_token,
        expires_in: sessionData.session.expires_in,
        expires_at: sessionData.session.expires_at,
        token_type: "bearer",
        restaurant_id: demoRestaurantId,
        role: clientRole,
        demo_session_id: demoSessionId,
        pairing_code: pairingCode,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: any) {
    return new Response(
      JSON.stringify({ error: err.message || "Failed to provision demo session." }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
