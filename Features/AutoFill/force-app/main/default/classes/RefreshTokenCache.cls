public with sharing class RefreshTokenCache {
    
    // Same partition you created
    private static final String PARTITION = 'local.FreightAuthApiToken';
    private static final String KEY       = 'FreightGraphRefreshToken';

    private static Cache.OrgPartition p() {
        return Cache.Org.getPartition(PARTITION);
    }

    public static void put(String refreshToken) {
        // store without TTL (let cache keep it until eviction)
        p().put(KEY, refreshToken);
    }

    public static String get() {
        Object v = p().get(KEY);
        return v == null ? null : (String)v;
    }

    public static void clear() {
        p().remove(KEY);
    }
}