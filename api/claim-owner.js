const { timingSafeEqual } = require('node:crypto');

function matchesSecret(provided, expected) {
  if (typeof provided !== 'string' || typeof expected !== 'string') return false;
  const providedBuffer = Buffer.from(provided);
  const expectedBuffer = Buffer.from(expected);
  return providedBuffer.length === expectedBuffer.length && timingSafeEqual(providedBuffer, expectedBuffer);
}

module.exports = async function claimOwner(request, response) {
  response.setHeader('Cache-Control', 'no-store');

  if (request.method !== 'POST') {
    response.setHeader('Allow', 'POST');
    return response.status(405).json({ error: 'Method not allowed.' });
  }

  const supabaseUrl = process.env.SUPABASE_URL?.replace(/\/$/, '');
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const ownerEmail = process.env.OWNER_EMAIL?.trim().toLowerCase();
  const setupToken = process.env.OWNER_SETUP_TOKEN;
  const suppliedSetupToken = request.headers['x-owner-setup-token'];
  const accessToken = request.body?.accessToken;

  if (!supabaseUrl || !serviceRoleKey || !ownerEmail || !setupToken || setupToken.length < 32) {
    return response.status(503).json({ error: 'Owner setup is not configured securely.' });
  }

  if (!matchesSecret(suppliedSetupToken, setupToken)) {
    return response.status(401).json({ error: 'Invalid setup authorization.' });
  }

  if (typeof accessToken !== 'string' || accessToken.length < 20) {
    return response.status(400).json({ error: 'A signed-in Supabase access token is required.' });
  }

  try {
    const userResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${accessToken}`
      }
    });

    if (!userResponse.ok) {
      return response.status(401).json({ error: 'The Supabase session is invalid or expired.' });
    }

    const user = await userResponse.json();
    if (!user.id || user.email?.trim().toLowerCase() !== ownerEmail) {
      return response.status(403).json({ error: 'This account is not the configured platform owner.' });
    }

    const claimResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/claim_platform_owner`, {
      method: 'POST',
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ p_user_id: user.id })
    });

    if (!claimResponse.ok) {
      const detail = await claimResponse.text();
      return response.status(409).json({ error: detail.includes('already been claimed') ? 'The platform owner has already been claimed.' : 'Could not claim the owner account.' });
    }

    return response.status(200).json({ claimed: true, displayName: 'مستر إياد الطيب | المؤرخ الصغير 📜' });
  } catch {
    return response.status(502).json({ error: 'Could not reach Supabase.' });
  }
};