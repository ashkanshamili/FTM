public with sharing class TokenCache {
    // Match your partition name exactly (you’re in a no-namespace org → prefix with 'local.')
    private static final String PARTITION = 'local.FreightAuthApiToken';
    private static final String KEY       = 'FreightGraphToken';

    private static Cache.OrgPartition p() {
        return Cache.Org.getPartition(PARTITION);
    }


    public static void put(String token, Integer ttlSeconds) {
        if (ttlSeconds != null && ttlSeconds > 0) {
            p().put(KEY, token, ttlSeconds);   // TTL version
        } else {
            p().put(KEY, token);               // no TTL
        }
    }

    public static String get() {
        Object v = p().get(KEY);
        return v == null ? null : (String)v;
    }

    public static void clear() {
        p().remove(KEY);
    }
}