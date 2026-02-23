import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const RECIPIENT = "info@connectionscuracao.net";
const FROM = "Spin & Win <noreply@connectionscuracao.net>";

Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey",
      },
    });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const { code, prize, jackpot } = await req.json();

    if (!code || !prize) {
      return new Response(JSON.stringify({ error: "Missing code or prize" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const timestamp = new Date().toLocaleString("en-US", {
      timeZone: "America/Curacao",
      dateStyle: "full",
      timeStyle: "short",
    });

    const subject = jackpot
      ? `🎰 JACKPOT WIN! Code ${code} just won ${prize}!`
      : `🎡 Spin Result: Code ${code} won ${prize}`;

    const html = `
      <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 480px; margin: 0 auto; padding: 24px;">
        ${jackpot ? `
        <div style="background: linear-gradient(135deg, #ffd60a, #ffaa00); color: #1a1a2e; padding: 20px; border-radius: 12px; text-align: center; margin-bottom: 24px;">
          <h1 style="margin: 0; font-size: 28px;">🎰 JACKPOT!</h1>
        </div>
        ` : `
        <div style="background: linear-gradient(135deg, #00d4ff, #2d7a9f); color: #fff; padding: 20px; border-radius: 12px; text-align: center; margin-bottom: 24px;">
          <h1 style="margin: 0; font-size: 24px;">🎡 Spin Result</h1>
        </div>
        `}
        <table style="width: 100%; border-collapse: collapse; font-size: 15px;">
          <tr>
            <td style="padding: 12px 0; border-bottom: 1px solid #eee; color: #666;">Code</td>
            <td style="padding: 12px 0; border-bottom: 1px solid #eee; font-weight: 600;">${code}</td>
          </tr>
          <tr>
            <td style="padding: 12px 0; border-bottom: 1px solid #eee; color: #666;">Prize</td>
            <td style="padding: 12px 0; border-bottom: 1px solid #eee; font-weight: 600; ${jackpot ? 'color: #e6a800;' : ''}">${prize}</td>
          </tr>
          <tr>
            <td style="padding: 12px 0; color: #666;">Time</td>
            <td style="padding: 12px 0;">${timestamp}</td>
          </tr>
        </table>
        <p style="margin-top: 24px; font-size: 13px; color: #999; text-align: center;">
          Connections Curacao — Spin & Win
        </p>
      </div>
    `;

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify({
        from: FROM,
        to: [RECIPIENT],
        subject,
        html,
      }),
    });

    const data = await res.json();

    if (!res.ok) {
      console.error("Resend API error:", data);
      return new Response(JSON.stringify({ error: "Email send failed" }), {
        status: 502,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (err) {
    console.error("Edge function error:", err);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  }
});
