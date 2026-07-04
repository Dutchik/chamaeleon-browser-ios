#include "chm_mitm.h"
#include "chm_proxy.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <pthread.h>

#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509v3.h>
#include <openssl/pem.h>
#include <openssl/rand.h>

static X509      *g_ca_cert = NULL;
static EVP_PKEY  *g_ca_key  = NULL;
static EVP_PKEY  *g_leaf_key = NULL;
static char       g_ca_der_path[1024] = {0};
static pthread_mutex_t g_ml = PTHREAD_MUTEX_INITIALIZER;

// host -> X509* リーフ証明書のキャッシュ
typedef struct leaf { char *host; X509 *cert; struct leaf *next; } leaf;
static leaf *g_leaves = NULL;

static EVP_PKEY *gen_key(void) { return EVP_RSA_gen(2048); }

static int write_file(const char *path, const void *data, long len) {
    FILE *f = fopen(path, "wb"); if (!f) return -1;
    fwrite(data, 1, (size_t)len, f); fclose(f); return 0;
}

// 自己署名ルートCAを生成
static int make_ca(const char *dir) {
    g_ca_key = gen_key();
    if (!g_ca_key) return -1;
    g_ca_cert = X509_new();
    X509_set_version(g_ca_cert, 2);
    ASN1_INTEGER_set(X509_get_serialNumber(g_ca_cert), 1);
    X509_gmtime_adj(X509_get_notBefore(g_ca_cert), -3600);
    X509_gmtime_adj(X509_get_notAfter(g_ca_cert), 3600L * 24 * 3650);
    X509_set_pubkey(g_ca_cert, g_ca_key);
    X509_NAME *nm = X509_get_subject_name(g_ca_cert);
    X509_NAME_add_entry_by_txt(nm, "CN", MBSTRING_ASC, (const unsigned char *)"Chamaeleon Local CA", -1, -1, 0);
    X509_NAME_add_entry_by_txt(nm, "O", MBSTRING_ASC, (const unsigned char *)"Chamaeleon", -1, -1, 0);
    X509_set_issuer_name(g_ca_cert, nm);
    // basicConstraints CA:TRUE
    X509V3_CTX ctx; X509V3_set_ctx_nodb(&ctx);
    X509V3_set_ctx(&ctx, g_ca_cert, g_ca_cert, NULL, NULL, 0);
    X509_EXTENSION *ext = X509V3_EXT_conf_nid(NULL, &ctx, NID_basic_constraints, "critical,CA:TRUE");
    if (ext) { X509_add_ext(g_ca_cert, ext, -1); X509_EXTENSION_free(ext); }
    ext = X509V3_EXT_conf_nid(NULL, &ctx, NID_key_usage, "critical,keyCertSign,cRLSign");
    if (ext) { X509_add_ext(g_ca_cert, ext, -1); X509_EXTENSION_free(ext); }
    if (!X509_sign(g_ca_cert, g_ca_key, EVP_sha256())) return -1;

    // 永続化: key(PEM), cert(PEM), cert(DER)
    char p[1024];
    snprintf(p, sizeof(p), "%s/chm_ca.key", dir);
    FILE *f = fopen(p, "wb"); if (f) { PEM_write_PrivateKey(f, g_ca_key, NULL, NULL, 0, NULL, NULL); fclose(f); }
    snprintf(p, sizeof(p), "%s/chm_ca.crt", dir);
    f = fopen(p, "wb"); if (f) { PEM_write_X509(f, g_ca_cert); fclose(f); }
    snprintf(g_ca_der_path, sizeof(g_ca_der_path), "%s/chm_ca.der", dir);
    unsigned char *der = NULL; int dl = i2d_X509(g_ca_cert, &der);
    if (dl > 0) { write_file(g_ca_der_path, der, dl); OPENSSL_free(der); }
    return 0;
}

static int load_ca(const char *dir) {
    char p[1024];
    snprintf(p, sizeof(p), "%s/chm_ca.key", dir);
    FILE *f = fopen(p, "rb"); if (!f) return -1;
    g_ca_key = PEM_read_PrivateKey(f, NULL, NULL, NULL); fclose(f);
    snprintf(p, sizeof(p), "%s/chm_ca.crt", dir);
    f = fopen(p, "rb"); if (!f) return -1;
    g_ca_cert = PEM_read_X509(f, NULL, NULL, NULL); fclose(f);
    if (!g_ca_key || !g_ca_cert) return -1;
    snprintf(g_ca_der_path, sizeof(g_ca_der_path), "%s/chm_ca.der", dir);
    return 0;
}

int chm_mitm_init(const char *ca_dir) {
    SSL_library_init();
    OpenSSL_add_all_algorithms();
    SSL_load_error_strings();
    pthread_mutex_lock(&g_ml);
    int rc = 0;
    if (!g_ca_cert) {
        if (load_ca(ca_dir) != 0) rc = make_ca(ca_dir);
        if (rc == 0 && !g_leaf_key) g_leaf_key = gen_key();
    }
    pthread_mutex_unlock(&g_ml);
    return (g_ca_cert && g_ca_key && g_leaf_key) ? 0 : -1;
}

const char *chm_mitm_ca_cert_der_path(void) { return g_ca_der_path[0] ? g_ca_der_path : NULL; }

// host用リーフ証明書を発行（キャッシュ）
static X509 *leaf_for(const char *host) {
    pthread_mutex_lock(&g_ml);
    for (leaf *l = g_leaves; l; l = l->next)
        if (strcmp(l->host, host) == 0) { X509 *c = l->cert; pthread_mutex_unlock(&g_ml); return c; }

    X509 *crt = X509_new();
    X509_set_version(crt, 2);
    unsigned char sn[8]; RAND_bytes(sn, sizeof(sn)); sn[0] &= 0x7f;
    BIGNUM *bn = BN_bin2bn(sn, sizeof(sn), NULL);
    ASN1_INTEGER *ai = BN_to_ASN1_INTEGER(bn, NULL);
    X509_set_serialNumber(crt, ai); ASN1_INTEGER_free(ai); BN_free(bn);
    X509_gmtime_adj(X509_get_notBefore(crt), -3600);
    X509_gmtime_adj(X509_get_notAfter(crt), 3600L * 24 * 397);
    X509_set_pubkey(crt, g_leaf_key);
    X509_NAME *nm = X509_get_subject_name(crt);
    X509_NAME_add_entry_by_txt(nm, "CN", MBSTRING_ASC, (const unsigned char *)host, -1, -1, 0);
    X509_set_issuer_name(crt, X509_get_subject_name(g_ca_cert));
    // SAN: DNS:host
    char san[1100]; snprintf(san, sizeof(san), "DNS:%s", host);
    X509V3_CTX ctx; X509V3_set_ctx_nodb(&ctx);
    X509V3_set_ctx(&ctx, g_ca_cert, crt, NULL, NULL, 0);
    X509_EXTENSION *ext = X509V3_EXT_conf_nid(NULL, &ctx, NID_subject_alt_name, san);
    if (ext) { X509_add_ext(crt, ext, -1); X509_EXTENSION_free(ext); }
    X509_sign(crt, g_ca_key, EVP_sha256());

    leaf *l = (leaf *)malloc(sizeof(leaf));
    l->host = strdup(host); l->cert = crt; l->next = g_leaves; g_leaves = l;
    pthread_mutex_unlock(&g_ml);
    return crt;
}

// SSL からヘッダ末尾まで読む（動的）
static long ssl_find_hdr_end(const char *b, long n) {
    for (long i = 3; i < n; i++)
        if (b[i-3]=='\r'&&b[i-2]=='\n'&&b[i-1]=='\r'&&b[i]=='\n') return i + 1;
    return -1;
}
static long ssl_content_length(const char *hdr) {
    const char *p = hdr;
    while (*p) {
        if ((p == hdr || p[-1] == '\n') && strncasecmp(p, "content-length:", 15) == 0) { p += 15; while (*p==' ') p++; return atol(p); }
        p++;
    }
    return -1;
}
static int ssl_has_chunked(const char *hdr) {
    const char *p = hdr;
    while (*p) {
        if ((p == hdr || p[-1] == '\n') && strncasecmp(p, "transfer-encoding:", 18) == 0) {
            const char *e = strchr(p, '\n'); if (!e) e = p + strlen(p);
            for (const char *q = p; q < e; q++) if (strncasecmp(q, "chunked", 7) == 0) return 1;
            return 0;
        }
        p++;
    }
    return 0;
}
static char *ssl_read_headers(SSL *s, long *total, long *hdrend) {
    long cap = 8192, n = 0; char *b = (char *)malloc(cap);
    for (;;) {
        if (n + 1 >= cap) { cap *= 2; char *nb = realloc(b, cap); if (!nb) break; b = nb; }
        int r = SSL_read(s, b + n, (int)(cap - n - 1));
        if (r <= 0) { if (n == 0) { free(b); *total = 0; *hdrend = -1; return NULL; } break; }
        n += r; b[n] = 0;
        long he = ssl_find_hdr_end(b, n);
        if (he >= 0) { *total = n; *hdrend = he; return b; }
        if (n > 262144) break;
    }
    *total = n; *hdrend = -1; return b;
}
static void ssl_write_all(SSL *s, const char *buf, long n) {
    long off = 0; while (off < n) { int w = SSL_write(s, buf + off, (int)(n - off)); if (w <= 0) return; off += w; }
}
static void send_rewritten(SSL *cli, char *buf, long hdrend, long bodylen) {
    char *hdr = (char *)malloc(hdrend + 1); memcpy(hdr, buf, hdrend); hdr[hdrend] = 0;
    char *out = (char *)malloc(hdrend + 256); long o = 0;
    char *line = hdr; int first = 1;
    while (line < hdr + hdrend) {
        char *eol = strstr(line, "\r\n"); if (!eol) break; long ll = eol - line; int skip = 0;
        if (!first) {
            if (strncasecmp(line, "content-length:", 15) == 0) skip = 1;
            if (strncasecmp(line, "transfer-encoding:", 18) == 0) skip = 1;
            if (strncasecmp(line, "connection:", 11) == 0) skip = 1;
        }
        if (!skip && ll > 0) { memcpy(out + o, line, ll); o += ll; out[o++]='\r'; out[o++]='\n'; }
        first = 0; line = eol + 2;
    }
    o += snprintf(out + o, 200, "Content-Length: %ld\r\nConnection: close\r\n\r\n", bodylen);
    ssl_write_all(cli, out, o);
    ssl_write_all(cli, buf + hdrend, bodylen);
    free(hdr); free(out);
}

int chm_mitm_bridge(int client_fd, const char *host, int origin_fd) {
    if (!g_ca_cert) return -1;
    X509 *leaf = leaf_for(host);

    // サーバ側(ブラウザ向け)
    SSL_CTX *sctx = SSL_CTX_new(TLS_server_method());
    SSL_CTX_use_certificate(sctx, leaf);
    SSL_CTX_add_extra_chain_cert(sctx, X509_dup(g_ca_cert));
    SSL_CTX_use_PrivateKey(sctx, g_leaf_key);
    SSL *cli = SSL_new(sctx); SSL_set_fd(cli, client_fd);
    if (SSL_accept(cli) <= 0) { SSL_free(cli); SSL_CTX_free(sctx); return -1; }

    // クライアント側(オリジン向け)。実験のため検証は既定パス＋失敗許容
    SSL_CTX *octx = SSL_CTX_new(TLS_client_method());
    SSL_CTX_set_default_verify_paths(octx);
    SSL *org = SSL_new(octx); SSL_set_fd(org, origin_fd);
    SSL_set_tlsext_host_name(org, host);
    X509_VERIFY_PARAM *vp = SSL_get0_param(org);
    X509_VERIFY_PARAM_set1_host(vp, host, 0);
    if (SSL_connect(org) <= 0) { SSL_free(cli); SSL_CTX_free(sctx); SSL_free(org); SSL_CTX_free(octx); return -1; }

    // 単一トランザクション: リクエスト転送 → レスポンス読取・書換 → 返却
    char urlhint[700] = {0};
    long rtot, rhe; char *req = ssl_read_headers(cli, &rtot, &rhe);
    if (req && rhe >= 0) {
        // リクエスト行のパスと host で URL ヒントを作る
        const char *sp = strchr(req, ' ');
        if (sp) { char pathbuf[512] = {0}; sp++; int j = 0;
            while (sp[j] && sp[j] != ' ' && j < 500) { pathbuf[j] = sp[j]; j++; } pathbuf[j] = 0;
            snprintf(urlhint, sizeof(urlhint), "https://%s%s", host, pathbuf); }
        long rcl = ssl_content_length(req);
        long have = rtot - rhe, cap = rtot + 1;
        while (rcl > 0 && have < rcl) {
            if (rtot + 1 >= cap) { cap *= 2; char *nb = realloc(req, cap); if (!nb) break; req = nb; }
            int r = SSL_read(cli, req + rtot, (int)(cap - rtot - 1)); if (r <= 0) break; rtot += r; have += r;
        }
        ssl_write_all(org, req, rtot);
    }
    free(req);

    long stot, she; char *res = ssl_read_headers(org, &stot, &she);
    if (res && she >= 0) {
        char save = res[she]; res[she] = 0;
        long cl = ssl_content_length(res); int chunked = ssl_has_chunked(res);
        res[she] = save;
        if (!chunked && cl >= 0) {
            long body_have = stot - she, scap = stot + 1;
            while (body_have < cl) {
                if (stot + 1 >= scap) { scap *= 2; char *nb = realloc(res, scap); if (!nb) break; res = nb; }
                int r = SSL_read(org, res + stot, (int)(scap - stot - 1)); if (r <= 0) break; stot += r; body_have += r;
            }
            // パケット層キャプチャ（HTTPSメディア本文を保存）
            chm_proxy_capture_if_media(res, she, res + she, cl, urlhint);
            long newlen = 0;
            char *nb = chm_proxy_rewrite_body(res + she, cl, &newlen);
            if (nb) {
                long tmp; char *full = (char *)malloc(she + newlen);
                memcpy(full, res, she); memcpy(full + she, nb, newlen);
                (void)tmp;
                send_rewritten(cli, full, she, newlen);
                free(full); free(nb);
            }
        } else {
            ssl_write_all(cli, res, stot);   // 書換不可はそのまま
        }
    }
    free(res);

    SSL_shutdown(cli); SSL_shutdown(org);
    SSL_free(cli); SSL_free(org);
    SSL_CTX_free(sctx); SSL_CTX_free(octx);
    return 0;
}
