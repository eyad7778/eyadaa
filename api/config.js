module.exports = function config(_request, response) {
  response.setHeader('Cache-Control', 'no-store');

  const supabaseUrl = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY;

  if (!supabaseUrl || !anonKey) {
    return response.status(503).json({ error: 'Supabase is not configured.' });
  }

  return response.status(200).json({
    supabaseUrl,
    anonKey,
    brandName: 'مستر إياد الطيب | المؤرخ الصغير 📜'
  });
};