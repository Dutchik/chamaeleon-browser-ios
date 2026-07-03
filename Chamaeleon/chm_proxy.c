#include "chm_proxy.h"
#include "chm_rules.h"
#include "chm_mitm.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>
#include <unistd.h>
#include <pthread.h>
#include <errno.h>
#include <signal.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netinet/in.h>

static int g_listen = -1;
static int g_running = 0;
static int g_port = 0;
static long g_bytes = 0;
static long g_rw_applied = 0;
static pthread_t g_accept_thread;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

typedef struct { char *find; char *repl; } rw_rule;
static rw_rule *g_rw = NULL;
static int g_rwn = 0, g_rwcap = 0;

// パケット層キャプチャ
static int  g_capture = 0;
static char g_capdir[1024] = {0};
static long g_capcount = 0;

static void add_bytes(long n) { pthread_mutex_lock(&g_lock); g_bytes += n; pthread_mutex_unlock(&g_lock); }

void chm_proxy_set_capture(const char *dir, int on) {
    pthread_mutex_lock(&g_lock);
    if (dir) { snprintf(g_capdir, sizeof(g_capdir), "%s", dir); }
    g_capture = on ? 1 : 0;
    pthread_mutex_unlock(&g_lock);
}
int chm_proxy_capture_enabled(void) { return g_capture; }
int chm_proxy_capture_count(void) { pthread_mutex_lock(&g_lock); int c = (int)g_capcount; pthread_mutex_unlock(&g_lock); return c; }

// Content-Type がメディアか（image/video/audio/pdf/octet-stream）
static int ct_is_media(const char *hdr) {
    const char *p = hdr;
    while (*p) {
        if ((p == hdr || p[-1] == '\n') && strncasecmp(p, "content-type:", 13) == 0) {
            const char *v = p + 13; while (*v == ' ') v++;
            if (strncasecmp(v, "image/", 6) == 0 || strncasecmp(v, "video/", 6) == 0 ||
                strncasecmp(v, "audio/", 6) == 0 || strncasecmp(v, "application/pdf", 15) == 0 ||
                strncasecmp(v, "application/octet-stream", 24) == 0) return 1;
            return 0;
        }
        p++;
    }
    return 0;
}
// Content-Type から拡張子を推定
static const char *ct_ext(const char *hdr) {
    const char *p = hdr;
    while (*p) {
        if ((p == hdr || p[-1] == '\n') && strncasecmp(p, "content-type:", 13) == 0) {
            const char *v = p + 13; while (*v == ' ') v++;
            if (!strncasecmp(v, "image/jpeg", 10)) return "jpg";
            if (!strncasecmp(v, "image/png", 9))  return "png";
            if (!strncasecmp(v, "image/gif", 9))  return "gif";
            if (!strncasecmp(v, "image/webp", 10)) return "webp";
            if (!strncasecmp(v, "image/svg", 9))  return "svg";
            if (!strncasecmp(v, "video/mp4", 9))  return "mp4";
            if (!strncasecmp(v, "video/webm", 10)) return "webm";
            if (!strncasecmp(v, "audio/mpeg", 10)) return "mp3";
            if (!strncasecmp(v, "application/pdf", 15)) return "pdf";
            return "bin";
        }
        p++;
    }
    return "bin";
}

// 応答がメディアならボディをキャプチャ保存
void chm_proxy_capture_if_media(const char *header, long headerlen,
                                const char *body, long bodylen, const char *url_hint) {
    if (!g_capture || !g_capdir[0] || bodylen <= 0) return;
    char *hdr = (char *)malloc(headerlen + 1);
    if (!hdr) return;
    memcpy(hdr, header, headerlen); hdr[headerlen] = 0;
    int media = ct_is_media(hdr);
    const char *ext = ct_ext(hdr);
    free(hdr);
    if (!media) return;

    long idx;
    pthread_mutex_lock(&g_lock); idx = ++g_capcount; pthread_mutex_unlock(&g_lock);

    // ファイル名: url_hint の末尾 + 連番、無ければ連番のみ
    char base[256] = {0};
    if (url_hint) {
        const char *slash = strrchr(url_hint, '/');
        const char *name = slash ? slash + 1 : url_hint;
        int j = 0;
        for (; name[j] && name[j] != '?' && name[j] != '#' && j < 200; j++) {
            char ch = name[j];
            base[j] = (ch == '/' || ch == '\\' || ch == ':') ? '_' : ch;
        }
        base[j] = 0;
    }
    char path[1400];
    if (base[0] && strchr(base, '.')) snprintf(path, sizeof(path), "%s/%ld_%s", g_capdir, idx, base);
    else snprintf(path, sizeof(path), "%s/%ld_capture.%s", g_capdir, idx, ext);

    FILE *f = fopen(path, "wb");
    if (f) { fwrite(body, 1, (size_t)bodylen, f); fclose(f); }
}

void chm_proxy_clear_rewrites(void) {
    pthread_mutex_lock(&g_lock);
    for (int i = 0; i < g_rwn; i++) { free(g_rw[i].find); free(g_rw[i].repl); }
    free(g_rw); g_rw = NULL; g_rwn = 0; g_rwcap = 0;
    pthread_mutex_unlock(&g_lock);
}
void chm_proxy_add_rewrite(const char *find, const char *replace) {
    if (!find || !*find || !replace) return;
    pthread_mutex_lock(&g_lock);
    if (g_rwn >= g_rwcap) {
        int cap = g_rwcap ? g_rwcap * 2 : 8;
        rw_rule *n = (rw_rule *)realloc(g_rw, sizeof(rw_rule) * cap);
        if (!n) { pthread_mutex_unlock(&g_lock); return; }
        g_rw = n; g_rwcap = cap;
    }
    g_rw[g_rwn].find = strdup(find);
    g_rw[g_rwn].repl = strdup(replace);
    g_rwn++;
    pthread_mutex_unlock(&g_lock);
}
long chm_proxy_rewrites_applied(void) {
    pthread_mutex_lock(&g_lock); long v = g_rw_applied; pthread_mutex_unlock(&g_lock); return v;
}
static int rw_count(void) { pthread_mutex_lock(&g_lock); int n = g_rwn; pthread_mutex_unlock(&g_lock); return n; }
int chm_proxy_rewrite_count(void) { return rw_count(); }

static int g_mitm = 0;
void chm_proxy_set_mitm(int on) { g_mitm = on ? 1 : 0; }
int chm_proxy_mitm_enabled(void) { return g_mitm; }

// body に全書換ルールを適用した新バッファ（malloc）を返す。
char *chm_proxy_rewrite_body(const char *body, long len, long *outlen) {
    char *buf = (char *)malloc(len > 0 ? len : 1);
    if (!buf) { *outlen = 0; return NULL; }
    if (len > 0) memcpy(buf, body, len);
    long blen = len, applied = 0;
    pthread_mutex_lock(&g_lock);
    for (int i = 0; i < g_rwn; i++) {
        const char *f = g_rw[i].find, *r = g_rw[i].repl;
        size_t fl = strlen(f), rl = strlen(r);
        if (fl == 0) continue;
        for (long pos = 0; pos + (long)fl <= blen; ) {
            if (memcmp(buf + pos, f, fl) == 0) {
                long nlen = blen - (long)fl + (long)rl;
                char *nb = (char *)malloc(nlen > 0 ? nlen : 1);
                if (!nb) { pos++; continue; }
                memcpy(nb, buf, pos);
                memcpy(nb + pos, r, rl);
                memcpy(nb + pos + rl, buf + pos + fl, blen - (pos + fl));
                free(buf); buf = nb; blen = nlen; pos += rl; applied++;
            } else pos++;
        }
    }
    if (applied) g_rw_applied += applied;
    pthread_mutex_unlock(&g_lock);
    *outlen = blen;
    return buf;
}

static int dial(const char *host, const char *port) {
    struct addrinfo hints, *res = NULL, *rp;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, port, &hints, &res) != 0) return -1;
    int fd = -1;
    for (rp = res; rp; rp = rp->ai_next) {
        fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
        if (fd < 0) continue;
        if (connect(fd, rp->ai_addr, rp->ai_addrlen) == 0) break;
        close(fd); fd = -1;
    }
    freeaddrinfo(res);
    return fd;
}

static void send_all(int fd, const char *s, long n) {
    long off = 0;
    while (off < n) { ssize_t w = send(fd, s + off, (size_t)(n - off), 0); if (w <= 0) return; off += w; }
}
static void send_str(int fd, const char *s) { send_all(fd, s, (long)strlen(s)); }

static void pump(int a, int b) {
    fd_set set; char buf[16384]; int maxfd = (a > b ? a : b) + 1;
    for (;;) {
        FD_ZERO(&set); FD_SET(a, &set); FD_SET(b, &set);
        if (select(maxfd, &set, NULL, NULL, NULL) < 0) { if (errno == EINTR) continue; break; }
        if (FD_ISSET(a, &set)) { ssize_t n = recv(a, buf, sizeof(buf), 0); if (n <= 0) break; send_all(b, buf, n); add_bytes(n); }
        if (FD_ISSET(b, &set)) { ssize_t n = recv(b, buf, sizeof(buf), 0); if (n <= 0) break; send_all(a, buf, n); add_bytes(n); }
    }
}

// ---- HTTP :80 本文書換 ----

static long find_header_end(const char *b, long n) {
    for (long i = 3; i < n; i++)
        if (b[i-3]=='\r'&&b[i-2]=='\n'&&b[i-1]=='\r'&&b[i]=='\n') return i + 1;
    return -1;
}
// ヘッダ文字列(null終端)から Content-Length を取得。無ければ -1
static long get_content_length(const char *hdr) {
    const char *p = hdr;
    while (*p) {
        if ((p == hdr || p[-1] == '\n') && strncasecmp(p, "content-length:", 15) == 0) {
            p += 15; while (*p == ' ') p++; return atol(p);
        }
        p++;
    }
    return -1;
}
static int header_has(const char *hdr, const char *key, const char *val) {
    const char *p = hdr; size_t kl = strlen(key);
    while (*p) {
        if ((p == hdr || p[-1] == '\n') && strncasecmp(p, key, kl) == 0) {
            const char *e = strchr(p, '\n'); if (!e) e = p + strlen(p);
            for (const char *q = p + kl; q < e; q++) if (strncasecmp(q, val, strlen(val)) == 0) return 1;
            return 0;
        }
        p++;
    }
    return 0;
}
// ヘッダ末尾までを1メッセージ読み切る（動的バッファ）。*hdrend はヘッダ終端index、-1で失敗
static char *read_until_headers(int fd, long *total, long *hdrend) {
    long cap = 8192, n = 0; char *b = (char *)malloc(cap);
    if (!b) { *total = 0; *hdrend = -1; return NULL; }
    for (;;) {
        if (n + 1 >= cap) { cap *= 2; char *nb = realloc(b, cap); if (!nb) break; b = nb; }
        ssize_t r = recv(fd, b + n, (size_t)(cap - n - 1), 0);
        if (r <= 0) { if (n == 0) { free(b); *total = 0; *hdrend = -1; return NULL; } break; }
        n += r; b[n] = 0;
        long he = find_header_end(b, n);
        if (he >= 0) { *total = n; *hdrend = he; return b; }
        if (n > 262144) break;   // ヘッダが異常に大きい
    }
    *total = n; *hdrend = -1; return b;
}
// buf の body 部分に全書換ルールを適用。新bufを返し *bodylen 更新
static char *apply_rewrites(char *buf, long hdrend, long *bodylen) {
    long applied = 0;
    pthread_mutex_lock(&g_lock);
    for (int i = 0; i < g_rwn; i++) {
        const char *f = g_rw[i].find, *r = g_rw[i].repl;
        size_t fl = strlen(f), rl = strlen(r);
        if (fl == 0) continue;
        for (long pos = hdrend; pos + (long)fl <= hdrend + *bodylen; ) {
            if (memcmp(buf + pos, f, fl) == 0) {
                long newbodylen = *bodylen - (long)fl + (long)rl;
                char *nb = (char *)malloc(hdrend + newbodylen + 1);
                if (!nb) { pos++; continue; }
                memcpy(nb, buf, pos);
                memcpy(nb + pos, r, rl);
                memcpy(nb + pos + rl, buf + pos + fl, (hdrend + *bodylen) - (pos + fl));
                free(buf); buf = nb; *bodylen = newbodylen;
                pos += rl; applied++;
            } else pos++;
        }
    }
    pthread_mutex_unlock(&g_lock);
    if (applied) { pthread_mutex_lock(&g_lock); g_rw_applied += applied; pthread_mutex_unlock(&g_lock); }
    return buf;
}
// Content-Length と Connection/Transfer-Encoding を書き換えたヘッダを送る
static void send_response_rewritten(int cfd, char *buf, long hdrend, long bodylen) {
    // ヘッダ行を再構築（CL/Connection/Transfer-Encoding を差し替え）
    char *hdr = (char *)malloc(hdrend + 1); memcpy(hdr, buf, hdrend); hdr[hdrend] = 0;
    char *out = (char *)malloc(hdrend + 256);
    long o = 0;
    char *line = hdr; int first = 1;
    while (line < hdr + hdrend) {
        char *eol = strstr(line, "\r\n"); if (!eol) break;
        long ll = eol - line;
        int skip = 0;
        if (!first) {
            if (strncasecmp(line, "content-length:", 15) == 0) skip = 1;
            if (strncasecmp(line, "transfer-encoding:", 18) == 0) skip = 1;
            if (strncasecmp(line, "connection:", 11) == 0) skip = 1;
        }
        if (!skip && ll > 0) { memcpy(out + o, line, ll); o += ll; out[o++] = '\r'; out[o++] = '\n'; }
        first = 0;
        line = eol + 2;
    }
    o += snprintf(out + o, 200, "Content-Length: %ld\r\nConnection: close\r\n\r\n", bodylen);
    send_all(cfd, out, o);
    send_all(cfd, buf + hdrend, bodylen);
    add_bytes(o + bodylen);
    free(hdr); free(out);
}

// CONNECT :80 の1トランザクションを本文書換つきで処理（Content-Length応答のみ書換、他はトンネル）
static void handle_http80(int cfd, int ofd) {
    // リクエスト: ヘッダ読み → body(CL) 読み → そのまま転送
    long rtot, rhe; char *req = read_until_headers(cfd, &rtot, &rhe);
    if (!req || rhe < 0) { if (req) free(req); pump(cfd, ofd); return; }
    // リクエスト行から URL パス（ファイル名ヒント）を取り出す
    char urlhint[512] = {0};
    { const char *sp = strchr(req, ' ');
      if (sp) { sp++; int j = 0; while (sp[j] && sp[j] != ' ' && j < 500) { urlhint[j] = sp[j]; j++; } urlhint[j] = 0; } }

    long rcl = get_content_length(req);
    long have = rtot - rhe, cap = rtot + 1;
    while (rcl > 0 && have < rcl) {
        if (rtot + 1 >= cap) { cap *= 2; char *nb = realloc(req, cap); if (!nb) break; req = nb; }
        ssize_t r = recv(cfd, req + rtot, (size_t)(cap - rtot - 1), 0);
        if (r <= 0) break; rtot += r; have += r;
    }
    send_all(ofd, req, rtot); add_bytes(rtot); free(req);

    // レスポンス: ヘッダ読み
    long stot, she; char *res = read_until_headers(ofd, &stot, &she);
    if (!res || she < 0) { if (res) { send_all(cfd, res, stot); free(res); } pump(cfd, ofd); return; }
    char save = res[she]; res[she] = 0;
    long cl = get_content_length(res);
    int chunked = header_has(res, "transfer-encoding:", "chunked");
    res[she] = save;

    if (chunked || cl < 0) {
        // 書換非対応 → そのまま流してトンネル継続
        send_all(cfd, res, stot); add_bytes(stot); free(res);
        pump(cfd, ofd); return;
    }
    // body を全部読む
    long body_have = stot - she, scap = stot + 1;
    while (body_have < cl) {
        if (stot + 1 >= scap) { scap *= 2; char *nb = realloc(res, scap); if (!nb) break; res = nb; }
        ssize_t r = recv(ofd, res + stot, (size_t)(scap - stot - 1), 0);
        if (r <= 0) break; stot += r; body_have += r;
    }
    // パケット層キャプチャ（実際に流れたメディア本文を保存。書換前の生バイト）
    chm_proxy_capture_if_media(res, she, res + she, cl, urlhint);

    long bodylen = cl;
    res = apply_rewrites(res, she, &bodylen);
    send_response_rewritten(cfd, res, she, bodylen);
    free(res);
    // 単一トランザクション + Connection: close
}

// ---- 接続処理 ----

static void *handle_conn(void *arg) {
    int cfd = (int)(long)arg;
    char line[4096];
    ssize_t n = recv(cfd, line, sizeof(line) - 1, 0);
    if (n <= 0) { close(cfd); return NULL; }
    line[n] = 0;

    if (strncmp(line, "CONNECT ", 8) == 0) {
        char host[1024] = {0}, port[16] = "443";
        char *sp = line + 8; char *end = strchr(sp, ' '); if (end) *end = 0;
        char *colon = strrchr(sp, ':'); if (colon) { *colon = 0; snprintf(port, sizeof(port), "%s", colon + 1); }
        snprintf(host, sizeof(host), "%s", sp);

        char urlbuf[1100];
        snprintf(urlbuf, sizeof(urlbuf), "https://%s/", host);
        if (chm_rules_eval(urlbuf) == 1) {
            send_str(cfd, "HTTP/1.1 403 Blocked\r\nContent-Length: 0\r\n\r\n");
            close(cfd); return NULL;
        }
        int ofd = dial(host, port);
        if (ofd < 0) { send_str(cfd, "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n"); close(cfd); return NULL; }
        send_str(cfd, "HTTP/1.1 200 Connection Established\r\n\r\n");
        // 先頭1バイトを覗いてTLS(0x16=ClientHello)か平文かを判定（ポート非依存）
        // 本文書換 or パケットキャプチャ が有効なとき、HTTPを解析するパスに入る
        int content_path = (rw_count() > 0) || g_capture;
        unsigned char peek = 0;
        if (content_path) recv(cfd, &peek, 1, MSG_PEEK);
        if (content_path && peek != 0x16) {
            handle_http80(cfd, ofd);                        // 平文HTTP → 書換/キャプチャ
        } else if (content_path && peek == 0x16 && chm_proxy_mitm_enabled()) {
            chm_mitm_bridge(cfd, host, ofd);                // TLS → MITMで書換/キャプチャ
        } else {
            pump(cfd, ofd);                                 // それ以外はトンネル
        }
        close(ofd); close(cfd);
        return NULL;
    }

    send_str(cfd, "HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\n\r\n");
    close(cfd);
    return NULL;
}

static void *accept_loop(void *arg) {
    (void)arg;
    while (g_running) {
        struct sockaddr_in cli; socklen_t clen = sizeof(cli);
        int cfd = accept(g_listen, (struct sockaddr *)&cli, &clen);
        if (cfd < 0) { if (g_running && errno == EINTR) continue; break; }
        pthread_t t;
        if (pthread_create(&t, NULL, handle_conn, (void *)(long)cfd) == 0) pthread_detach(t);
        else close(cfd);
    }
    return NULL;
}

int chm_proxy_start(int port) {
    if (g_running) return g_port;
    signal(SIGPIPE, SIG_IGN);
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return 0;
    int yes = 1; setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in addr; memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET; addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons((uint16_t)(port < 0 ? 0 : port));
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) { close(fd); return 0; }
    if (listen(fd, 64) != 0) { close(fd); return 0; }
    socklen_t alen = sizeof(addr);
    if (getsockname(fd, (struct sockaddr *)&addr, &alen) != 0) { close(fd); return 0; }
    g_port = ntohs(addr.sin_port);
    g_listen = fd; g_running = 1;
    if (pthread_create(&g_accept_thread, NULL, accept_loop, NULL) != 0) { g_running = 0; close(fd); g_listen = -1; return 0; }
    return g_port;
}

void chm_proxy_stop(void) {
    if (!g_running) return;
    g_running = 0;
    if (g_listen >= 0) { shutdown(g_listen, SHUT_RDWR); close(g_listen); g_listen = -1; }
    pthread_join(g_accept_thread, NULL);
    g_port = 0;
}

int chm_proxy_running(void) { return g_running; }
long chm_proxy_bytes(void) { pthread_mutex_lock(&g_lock); long b = g_bytes; pthread_mutex_unlock(&g_lock); return b; }
